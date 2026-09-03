#include "doltlite_result.h"
#include "doltlite_connection.h"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>

/* ------------------------------------------------------------ type rules -- */

/* SQLite's own affinity rules, applied to the declared type. An expression has
 * no declared type, which is why DT_UNKNOWN exists and why promotion below
 * has to cope with a column whose type is only learned from its values. */
static DType dtype_from_decl(const char *decl) {
  if (decl == NULL || decl[0] == '\0') return DT_UNKNOWN;

  std::string d;
  for (const char *p = decl; *p; ++p) {
    d += (char) toupper((unsigned char) *p);
  }
  if (d.find("INT") != std::string::npos) return DT_INT;
  if (d.find("CHAR") != std::string::npos || d.find("CLOB") != std::string::npos ||
      d.find("TEXT") != std::string::npos)
    return DT_TEXT;
  if (d.find("BLOB") != std::string::npos) return DT_BLOB;
  if (d.find("REAL") != std::string::npos || d.find("FLOA") != std::string::npos ||
      d.find("DOUB") != std::string::npos)
    return DT_REAL;
  /* NUMERIC and DECIMAL affinity: treat as double, as RSQLite does. */
  return DT_REAL;
}

/* Widen `have` just enough to also hold `want`. The ordering is
 * INT < INT64 < REAL < TEXT, with BLOB absorbing everything, which matches
 * both SQLite's own conversions and what an R user expects to get back. */
static DType promote(DType have, DType want) {
  if (want == DT_UNKNOWN) return have;
  if (have == DT_UNKNOWN || have == DT_LGL) return want;
  if (have == want) return have;
  if (have == DT_BLOB || want == DT_BLOB) return DT_BLOB;
  if (have == DT_TEXT || want == DT_TEXT) return DT_TEXT;
  if (have == DT_REAL || want == DT_REAL) return DT_REAL;
  if (have == DT_INT64 || want == DT_INT64) return DT_INT64;
  return DT_INT;
}

/* SQLite stores text as UTF-8, but a caller in a non-UTF-8 locale can push
 * bytes through that are not. Marking those CE_UTF8 makes R warn ("cannot be
 * translated to UTF-8") and breaks round-tripping, so validate first and fall
 * back to the native encoding. */
static bool is_valid_utf8(const char *s, size_t n) {
  const unsigned char *p = (const unsigned char *) s;
  size_t i = 0;
  while (i < n) {
    unsigned char c = p[i];
    size_t extra;
    unsigned int cp;

    if (c < 0x80) { i += 1; continue; }
    else if ((c & 0xE0) == 0xC0) { extra = 1; cp = c & 0x1F; }
    else if ((c & 0xF0) == 0xE0) { extra = 2; cp = c & 0x0F; }
    else if ((c & 0xF8) == 0xF0) { extra = 3; cp = c & 0x07; }
    else return false;

    if (i + extra >= n) return false;   /* continuation bytes must all exist */
    for (size_t k = 1; k <= extra; ++k) {
      unsigned char cc = p[i + k];
      if ((cc & 0xC0) != 0x80) return false;
      cp = (cp << 6) | (cc & 0x3F);
    }
    /* Reject overlong forms, surrogates, and out-of-range code points. */
    if (extra == 1 && cp < 0x80) return false;
    if (extra == 2 && cp < 0x800) return false;
    if (extra == 3 && cp < 0x10000) return false;
    if (cp > 0x10FFFF) return false;
    if (cp >= 0xD800 && cp <= 0xDFFF) return false;
    i += extra + 1;
  }
  return true;
}

static SEXP mk_char(const std::string &s) {
  return Rf_mkCharLenCE(s.data(), (int) s.size(),
                        is_valid_utf8(s.data(), s.size()) ? CE_UTF8 : CE_NATIVE);
}

static bool fits_in_int(sqlite3_int64 v) {
  /* NA_INTEGER is INT_MIN, so it is not available as a value. */
  return v > (sqlite3_int64) INT_MIN && v <= (sqlite3_int64) INT_MAX;
}

/* ---------------------------------------------------------------- result -- */

DoltliteResult::DoltliteResult(DoltliteConnection *conn, const std::string &sql)
    : conn_(conn), stmt_(NULL), sql_(sql), ncol_(0), completed_(false),
      bound_(false), needs_bind_(false), have_row_(false),
      rows_affected_(NA_INTEGER), rows_fetched_(0), bigint_(conn->bigint()),
      params_(R_NilValue), nsets_(0), cur_set_(0) {
  sqlite3 *db = conn->check();

  const char *tail = NULL;
  int rc = sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt_, &tail);
  if (rc != SQLITE_OK) {
    if (stmt_) {
      sqlite3_finalize(stmt_);
      stmt_ = NULL;
    }
    throw std::runtime_error(std::string(sqlite3_errmsg(db)));
  }
  if (stmt_ == NULL) {
    /* Whitespace or a bare comment: nothing to run. */
    throw std::runtime_error("nothing to execute");
  }

  /* Reject a second statement outright instead of silently running only the
   * first, which is what a bare sqlite3_prepare_v2 would do. */
  if (tail != NULL) {
    while (*tail && (isspace((unsigned char) *tail) || *tail == ';')) ++tail;
    if (*tail != '\0') {
      sqlite3_finalize(stmt_);
      stmt_ = NULL;
      throw std::runtime_error(
          "cannot run more than one statement at a time; got trailing text: '" +
          std::string(tail) + "'");
    }
  }

  conn_->register_result(this);

  /* Everything below can throw -- step_once() raises on a constraint
   * violation, for instance. A constructor that throws does not run its own
   * destructor, so without this the connection would keep a registered
   * pointer to storage that is about to be freed, and the next disconnect
   * would walk into it. */
  try {
    init_columns();

    needs_bind_ = sqlite3_bind_parameter_count(stmt_) > 0;

    /* A statement with no result columns is DML/DDL: run it now, so that
     * dbSendStatement()/dbExecute() take effect without needing a fetch.
     *
     * Only when it takes no parameters, though. Running a parameterised
     * statement here would execute it once with everything bound to NULL --
     * which is how dbWriteTable() ended up inserting a phantom all-NA row
     * before the real rows -- and bind() would then run it again per set. */
    if (ncol_ == 0 && !needs_bind_) {
      step_once();
    } else if (ncol_ > 0 && !needs_bind_) {
      /* Peek one row so that dbColumnInfo() can report real types before the
       * first fetch. An expression column has no declared type at all, so
       * without this a CAST(... AS INTEGER) would be reported as logical. The
       * row stays queued in have_row_ and is handed to the first fetch. */
      step_once();
      infer_types();
    }
  } catch (...) {
    conn_->unregister_result(this);
    if (stmt_ != NULL) {
      sqlite3_finalize(stmt_);
      stmt_ = NULL;
    }
    throw;
  }
}

DoltliteResult::~DoltliteResult() {
  try {
    close();
  } catch (...) {
  }
}

void DoltliteResult::init_columns() {
  ncol_ = sqlite3_column_count(stmt_);
  names_.resize(ncol_);
  decltypes_.resize(ncol_);
  types_.resize(ncol_);
  buf_.resize(ncol_);
  for (int j = 0; j < ncol_; ++j) {
    const char *nm = sqlite3_column_name(stmt_, j);
    names_[j] = nm ? nm : "";
    const char *dt = sqlite3_column_decltype(stmt_, j);
    decltypes_[j] = dt ? dt : "";
    types_[j] = dtype_from_decl(dt);
  }
}

void DoltliteResult::require_active() const {
  if (stmt_ == NULL) {
    throw std::runtime_error("this result set has been cleared");
  }
}

/* Reaching for results before binding is a programming error, and a much
 * clearer one to report than whatever the all-NULL execution would produce. */
void DoltliteResult::require_bound() const {
  if (needs_bind_ && !bound_) {
    char buf[160];
    std::snprintf(buf, sizeof buf,
                  "this statement takes %d parameter%s that have not been "
                  "bound; call dbBind() first, or pass `params=`",
                  sqlite3_bind_parameter_count(stmt_),
                  sqlite3_bind_parameter_count(stmt_) == 1 ? "" : "s");
    throw std::runtime_error(buf);
  }
}

void DoltliteResult::close() {
  release_params();
  if (stmt_ == NULL) return;
  sqlite3_stmt *st = stmt_;
  stmt_ = NULL;
  if (conn_ != NULL) conn_->unregister_result(this);
  sqlite3_finalize(st);
  buf_.clear();
}

void DoltliteResult::notify_connection_closed() {
  release_params();
  /* The connection is going away, so the statement handle is about to become
   * unusable. Finalize it while the sqlite3 handle is still alive, then forget
   * the connection so close() cannot dereference it later. */
  if (stmt_ != NULL) {
    sqlite3_stmt *st = stmt_;
    stmt_ = NULL;
    sqlite3_finalize(st);
  }
  conn_ = NULL;
  buf_.clear();
}

int DoltliteResult::parameter_count() const {
  require_active();
  return sqlite3_bind_parameter_count(stmt_);
}

void DoltliteResult::step_once() {
  require_active();
  int rc;

  for (;;) {
    rc = sqlite3_step(stmt_);
    if (rc == SQLITE_ROW) {
      have_row_ = true;
      return;
    }
    if (rc != SQLITE_DONE) break;

    /* A query bound to several parameter sets runs once per set and returns
     * the concatenation, so exhausting one set is not the end of the result --
     * rebind and keep going. Statements are driven by bind() itself, which is
     * why this only applies when there are result columns. */
    if (ncol_ > 0 && cur_set_ + 1 < nsets_) {
      ++cur_set_;
      bind_set(cur_set_);
      continue;
    }

    have_row_ = false;
    completed_ = true;
    if (conn_ != NULL) {
      rows_affected_ = sqlite3_changes(conn_->check());
    }
    return;
  }

  /* Surface the busy classes explicitly: they are the documented DoltLite
   * outcome for a second concurrent writer, and are retryable, which a bare
   * "database is locked" does not convey. */
  std::string msg = conn_ != NULL ? sqlite3_errmsg(conn_->check())
                                  : sqlite3_errstr(rc);
  int base = rc & 0xff;
  if (base == SQLITE_BUSY) {
    if (rc == SQLITE_BUSY_SNAPSHOT) {
      msg += "\nAnother connection advanced the database after this "
             "transaction took its read snapshot. Roll back and retry.";
    } else {
      msg += "\nDoltLite allows one durable writer at a time. Retry, or raise "
             "the busy timeout via dbConnect(..., busy_timeout=).";
    }
  }
  have_row_ = false;
  completed_ = true;
  throw std::runtime_error(msg);
}

/* ---------------------------------------------------------------- binding -- */

void DoltliteResult::bind_one(int idx, SEXP col, int row) {
  int rc = SQLITE_OK;

  switch (TYPEOF(col)) {
    case LGLSXP: {
      int v = LOGICAL(col)[row];
      rc = (v == NA_LOGICAL) ? sqlite3_bind_null(stmt_, idx)
                             : sqlite3_bind_int(stmt_, idx, v);
      break;
    }
    case INTSXP: {
      int v = INTEGER(col)[row];
      rc = (v == NA_INTEGER) ? sqlite3_bind_null(stmt_, idx)
                             : sqlite3_bind_int(stmt_, idx, v);
      break;
    }
    case REALSXP: {
      double v = REAL(col)[row];
      if (Rf_inherits(col, "integer64")) {
        /* bit64 stores an int64 in the bit pattern of a double. */
        sqlite3_int64 iv;
        std::memcpy(&iv, &v, sizeof iv);
        rc = (iv == std::numeric_limits<sqlite3_int64>::min())
                 ? sqlite3_bind_null(stmt_, idx)
                 : sqlite3_bind_int64(stmt_, idx, iv);
      } else {
        rc = ISNA(v) ? sqlite3_bind_null(stmt_, idx)
                     : sqlite3_bind_double(stmt_, idx, v);
      }
      break;
    }
    case STRSXP: {
      SEXP e = STRING_ELT(col, row);
      if (e == NA_STRING) {
        rc = sqlite3_bind_null(stmt_, idx);
      } else {
        const char *txt = Rf_translateCharUTF8(e);
        rc = sqlite3_bind_text(stmt_, idx, txt, -1, SQLITE_TRANSIENT);
      }
      break;
    }
    case VECSXP: {
      /* A list column carries blobs (raw vectors), as blob::blob does. */
      SEXP e = VECTOR_ELT(col, row);
      if (e == R_NilValue) {
        rc = sqlite3_bind_null(stmt_, idx);
      } else if (TYPEOF(e) == RAWSXP) {
        R_xlen_t n = Rf_xlength(e);
        rc = sqlite3_bind_blob(stmt_, idx, n ? (const void *) RAW(e) : "",
                               (int) n, SQLITE_TRANSIENT);
      } else {
        throw std::runtime_error(
            "list parameters must contain raw vectors (blobs) or NULL");
      }
      break;
    }
    default:
      throw std::runtime_error(
          "unsupported parameter type; use logical, integer, double, "
          "character, integer64, or a list of raw vectors");
  }

  if (rc != SQLITE_OK) {
    throw std::runtime_error(std::string("could not bind parameter: ") +
                             sqlite3_errstr(rc));
  }
}

void DoltliteResult::release_params() {
  if (params_ != R_NilValue) {
    R_ReleaseObject(params_);
    params_ = R_NilValue;
  }
  param_index_.clear();
  nsets_ = 0;
  cur_set_ = 0;
}

/* Reset the statement and bind parameter set `row`. Placeholder positions were
 * resolved once in bind(), so this is just the value binding. */
void DoltliteResult::bind_set(R_xlen_t row) {
  sqlite3_reset(stmt_);
  sqlite3_clear_bindings(stmt_);

  int supplied = (params_ == R_NilValue) ? 0 : (int) Rf_xlength(params_);
  for (int j = 0; j < supplied; ++j) {
    SEXP col = VECTOR_ELT(params_, j);
    R_xlen_t len = Rf_xlength(col);
    bind_one(param_index_[j], col, (int) (len == 1 ? 0 : row));
  }
  completed_ = false;
  have_row_ = false;
}

void DoltliteResult::bind(SEXP params) {
  require_active();

  int expected = sqlite3_bind_parameter_count(stmt_);
  int supplied = (params == R_NilValue) ? 0 : (int) Rf_xlength(params);

  if (expected == 0) {
    throw std::runtime_error(
        "this statement takes no parameters, so there is nothing to bind");
  }

  if (supplied != expected) {
    char buf[160];
    std::snprintf(buf, sizeof buf,
                  "the statement takes %d parameter%s but %d %s supplied",
                  expected, expected == 1 ? "" : "s", supplied,
                  supplied == 1 ? "was" : "were");
    throw std::runtime_error(buf);
  }

  /* Named parameters are matched by name when names are present, otherwise
   * positionally, so both list(1, 2) and list(a = 1, b = 2) work. */
  SEXP nms = (params == R_NilValue) ? R_NilValue
                                    : Rf_getAttrib(params, R_NamesSymbol);
  bool named = (nms != R_NilValue) && (Rf_xlength(nms) == supplied);

  /* If the statement uses named placeholders (:x, @x, $x), unnamed values
   * must not be silently bound by position -- DBI requires an error. */
  if (!named) {
    for (int i = 1; i <= expected; ++i) {
      const char *pn = sqlite3_bind_parameter_name(stmt_, i);
      /* "$1" and "?1" are numbered, i.e. still positional; only a non-digit
       * after the sigil makes a placeholder genuinely named. */
      if (pn != NULL && (pn[0] == ':' || pn[0] == '@' || pn[0] == '$') &&
          pn[1] != '\0' && !isdigit((unsigned char) pn[1])) {
        throw std::runtime_error(
            std::string("this statement uses named parameters (") + pn +
            "), so the values must be named too");
      }
    }
  }

  /* One parameter set per row. Length-1 values are recycled; anything else
   * must agree. */
  R_xlen_t nrow = 1;
  bool empty = false;
  for (int j = 0; j < supplied; ++j) {
    R_xlen_t len = Rf_xlength(VECTOR_ELT(params, j));
    if (len == 0) {
      empty = true;
    } else if (len > nrow) {
      if (nrow > 1) {
        throw std::runtime_error("parameter values must all have the same length");
      }
      nrow = len;
    }
  }
  for (int j = 0; j < supplied; ++j) {
    R_xlen_t len = Rf_xlength(VECTOR_ELT(params, j));
    if (!empty && len != 1 && len != nrow) {
      throw std::runtime_error("parameter values must all have the same length");
    }
  }
  if (empty) nrow = 0;

  release_params();
  if (params != R_NilValue) {
    R_PreserveObject(params);
    params_ = params;
  }

  /* Resolve placeholder positions once rather than per parameter set. */
  param_index_.assign(supplied, 0);
  for (int j = 0; j < supplied; ++j) {
    if (!named) {
      param_index_[j] = j + 1;
      continue;
    }
    std::string nm = Rf_translateChar(STRING_ELT(nms, j));
    int idx = sqlite3_bind_parameter_index(stmt_, nm.c_str());
    /* Accept a bare name as well as SQLite's :name / $name / @name forms. */
    if (idx == 0) idx = sqlite3_bind_parameter_index(stmt_, (":" + nm).c_str());
    if (idx == 0) idx = sqlite3_bind_parameter_index(stmt_, ("$" + nm).c_str());
    if (idx == 0) idx = sqlite3_bind_parameter_index(stmt_, ("@" + nm).c_str());
    if (idx == 0) {
      release_params();
      throw std::runtime_error("the statement has no parameter named '" + nm + "'");
    }
    param_index_[j] = idx;
  }

  nsets_ = nrow;
  cur_set_ = 0;
  completed_ = false;
  have_row_ = false;
  rows_fetched_ = 0;
  rows_affected_ = NA_INTEGER;

  if (nrow == 0) {
    /* Zero-length parameters: nothing to bind, nothing to run, nothing
     * affected -- but the result is legitimately complete. */
    sqlite3_reset(stmt_);
    sqlite3_clear_bindings(stmt_);
    completed_ = true;
    if (ncol_ == 0) rows_affected_ = 0;
    bound_ = true;
    return;
  }

  if (ncol_ == 0) {
    /* A statement: run every parameter set now and report the total, which is
     * what dbExecute() with a parameter data frame should give back. */
    int total = 0;
    for (R_xlen_t i = 0; i < nrow; ++i) {
      bind_set(i);
      step_once();
      if (rows_affected_ != NA_INTEGER) total += rows_affected_;
    }
    rows_affected_ = total;
    completed_ = true;
  } else {
    bind_set(0);
    step_once();
    infer_types();
  }

  bound_ = true;
}

/* ---------------------------------------------------------------- fetching -- */

/* Widen column j to also admit the value currently sitting in the statement.
 * Split out from collect_row() so that the same rules can be applied to a row
 * that has only been peeked at, which is what makes dbColumnInfo() accurate
 * before the first fetch. */
void DoltliteResult::update_type(int j) {
  switch (sqlite3_column_type(stmt_, j)) {
    case SQLITE_INTEGER: {
      sqlite3_int64 v = sqlite3_column_int64(stmt_, j);
      if (!fits_in_int(v) &&
          (types_[j] == DT_INT || types_[j] == DT_UNKNOWN)) {
        switch (bigint_) {
          case BIGINT_INTEGER64: types_[j] = promote(types_[j], DT_INT64); break;
          case BIGINT_NUMERIC:   types_[j] = promote(types_[j], DT_REAL);  break;
          case BIGINT_CHARACTER: types_[j] = promote(types_[j], DT_TEXT);  break;
          case BIGINT_INTEGER:   types_[j] = promote(types_[j], DT_INT);   break;
        }
      } else {
        types_[j] = promote(types_[j], DT_INT);
      }
      break;
    }
    case SQLITE_FLOAT: types_[j] = promote(types_[j], DT_REAL); break;
    case SQLITE_TEXT:  types_[j] = promote(types_[j], DT_TEXT); break;
    case SQLITE_BLOB:  types_[j] = promote(types_[j], DT_BLOB); break;
    default: /* SQLITE_NULL carries no type information */ break;
  }
}

void DoltliteResult::infer_types() {
  if (!have_row_) return;
  for (int j = 0; j < ncol_; ++j) update_type(j);
}

void DoltliteResult::collect_row() {
  for (int j = 0; j < ncol_; ++j) {
    Cell c;
    c.type = sqlite3_column_type(stmt_, j);

    switch (c.type) {
      case SQLITE_INTEGER:
        c.i = sqlite3_column_int64(stmt_, j);
        break;
      case SQLITE_FLOAT:
        c.d = sqlite3_column_double(stmt_, j);
        break;
      case SQLITE_TEXT: {
        const unsigned char *t = sqlite3_column_text(stmt_, j);
        int n = sqlite3_column_bytes(stmt_, j);
        c.s.assign(t ? (const char *) t : "", n);
        break;
      }
      case SQLITE_BLOB: {
        const void *b = sqlite3_column_blob(stmt_, j);
        int n = sqlite3_column_bytes(stmt_, j);
        c.s.assign(b ? (const char *) b : "", n);
        break;
      }
      default:
        break;
    }
    update_type(j);
    buf_[j].push_back(c);
  }
  ++rows_fetched_;
}

static void set_int64_na(double *slot) {
  sqlite3_int64 na = std::numeric_limits<sqlite3_int64>::min();
  std::memcpy(slot, &na, sizeof na);
}

SEXP DoltliteResult::materialise(int nrow) {
  SEXP out = PROTECT(Rf_allocVector(VECSXP, ncol_));
  SEXP nms = PROTECT(Rf_allocVector(STRSXP, ncol_));

  for (int j = 0; j < ncol_; ++j) {
    SET_STRING_ELT(nms, j, Rf_mkCharCE(names_[j].c_str(), CE_UTF8));

    /* A column that only ever held NULL has no type to infer. R's own
     * convention for a typeless all-NA column is logical, and it is what
     * DBI/RSQLite return, so it converts cleanly to anything downstream. */
    DType t = types_[j];
    if (t == DT_UNKNOWN) t = DT_LGL;

    SEXP col;
    switch (t) {
      case DT_LGL: {
        col = PROTECT(Rf_allocVector(LGLSXP, nrow));
        for (int i = 0; i < nrow; ++i) LOGICAL(col)[i] = NA_LOGICAL;
        break;
      }
      case DT_INT: {
        col = PROTECT(Rf_allocVector(INTSXP, nrow));
        for (int i = 0; i < nrow; ++i) {
          const Cell &c = buf_[j][i];
          if (c.type == SQLITE_NULL) {
            INTEGER(col)[i] = NA_INTEGER;
          } else if (c.type == SQLITE_INTEGER) {
            INTEGER(col)[i] = fits_in_int(c.i) ? (int) c.i : NA_INTEGER;
          } else if (c.type == SQLITE_FLOAT) {
            INTEGER(col)[i] = (int) c.d;
          } else {
            INTEGER(col)[i] = NA_INTEGER;
          }
        }
        break;
      }
      case DT_INT64: {
        col = PROTECT(Rf_allocVector(REALSXP, nrow));
        for (int i = 0; i < nrow; ++i) {
          const Cell &c = buf_[j][i];
          if (c.type == SQLITE_INTEGER) {
            sqlite3_int64 v = c.i;
            std::memcpy(&REAL(col)[i], &v, sizeof v);
          } else if (c.type == SQLITE_FLOAT) {
            sqlite3_int64 v = (sqlite3_int64) c.d;
            std::memcpy(&REAL(col)[i], &v, sizeof v);
          } else {
            set_int64_na(&REAL(col)[i]);
          }
        }
        Rf_setAttrib(col, R_ClassSymbol, Rf_mkString("integer64"));
        break;
      }
      case DT_REAL: {
        col = PROTECT(Rf_allocVector(REALSXP, nrow));
        for (int i = 0; i < nrow; ++i) {
          const Cell &c = buf_[j][i];
          if (c.type == SQLITE_NULL) {
            REAL(col)[i] = NA_REAL;
          } else if (c.type == SQLITE_INTEGER) {
            REAL(col)[i] = (double) c.i;
          } else if (c.type == SQLITE_FLOAT) {
            REAL(col)[i] = c.d;
          } else {
            REAL(col)[i] = NA_REAL;
          }
        }
        break;
      }
      case DT_TEXT: {
        col = PROTECT(Rf_allocVector(STRSXP, nrow));
        for (int i = 0; i < nrow; ++i) {
          const Cell &c = buf_[j][i];
          if (c.type == SQLITE_NULL) {
            SET_STRING_ELT(col, i, NA_STRING);
          } else if (c.type == SQLITE_TEXT || c.type == SQLITE_BLOB) {
            SET_STRING_ELT(col, i, mk_char(c.s));
          } else if (c.type == SQLITE_INTEGER) {
            char b[32];
            std::snprintf(b, sizeof b, "%lld", (long long) c.i);
            SET_STRING_ELT(col, i, Rf_mkChar(b));
          } else {
            /* %.17g round-trips a double exactly. */
            char b[64];
            std::snprintf(b, sizeof b, "%.17g", c.d);
            SET_STRING_ELT(col, i, Rf_mkChar(b));
          }
        }
        break;
      }
      case DT_BLOB:
      default: {
        col = PROTECT(Rf_allocVector(VECSXP, nrow));
        for (int i = 0; i < nrow; ++i) {
          const Cell &c = buf_[j][i];
          if (c.type == SQLITE_NULL) {
            SET_VECTOR_ELT(col, i, R_NilValue);
          } else {
            SEXP raw = PROTECT(Rf_allocVector(RAWSXP, c.s.size()));
            if (!c.s.empty()) {
              std::memcpy(RAW(raw), c.s.data(), c.s.size());
            }
            SET_VECTOR_ELT(col, i, raw);
            UNPROTECT(1);
          }
        }
        break;
      }
    }

    SET_VECTOR_ELT(out, j, col);
    UNPROTECT(1); /* col */
  }

  Rf_setAttrib(out, R_NamesSymbol, nms);
  UNPROTECT(2);
  return out;
}

SEXP DoltliteResult::fetch(int n) {
  require_active();
  require_bound();

  if (ncol_ == 0) {
    /* A statement has no rows to give. Returning a zero-column, zero-row
     * frame keeps dbFetch() on a statement from erroring out. */
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 0));
    Rf_setAttrib(out, R_NamesSymbol, Rf_allocVector(STRSXP, 0));
    UNPROTECT(1);
    return out;
  }

  for (int j = 0; j < ncol_; ++j) buf_[j].clear();

  int fetched = 0;
  bool unlimited = (n < 0);

  while (unlimited || fetched < n) {
    if (!have_row_) {
      if (completed_) break;
      step_once();
      if (!have_row_) break;
    }
    collect_row();
    have_row_ = false;
    ++fetched;
  }

  /* Peek ahead so that dbHasCompleted() is accurate straight after a fetch
   * that happened to consume exactly the remaining rows. */
  if (!unlimited && !completed_ && !have_row_) {
    step_once();
  }

  SEXP data = PROTECT(materialise(fetched));
  for (int j = 0; j < ncol_; ++j) buf_[j].clear();
  UNPROTECT(1);
  return data;
}

SEXP DoltliteResult::column_info() {
  require_active();

  SEXP name = PROTECT(Rf_allocVector(STRSXP, ncol_));
  SEXP type = PROTECT(Rf_allocVector(STRSXP, ncol_));
  SEXP decl = PROTECT(Rf_allocVector(STRSXP, ncol_));

  for (int j = 0; j < ncol_; ++j) {
    SET_STRING_ELT(name, j, Rf_mkCharCE(names_[j].c_str(), CE_UTF8));
    SET_STRING_ELT(decl, j, Rf_mkChar(decltypes_[j].c_str()));

    const char *rt;
    switch (types_[j] == DT_UNKNOWN ? DT_LGL : types_[j]) {
      case DT_LGL:   rt = "logical";    break;
      case DT_INT:   rt = "integer";    break;
      case DT_INT64: rt = "integer64";  break;
      case DT_REAL:  rt = "numeric";    break;
      case DT_TEXT:  rt = "character";  break;
      default:       rt = "list";       break;
    }
    SET_STRING_ELT(type, j, Rf_mkChar(rt));
  }

  SEXP out = PROTECT(Rf_allocVector(VECSXP, 3));
  SEXP nms = PROTECT(Rf_allocVector(STRSXP, 3));
  SET_STRING_ELT(nms, 0, Rf_mkChar("name"));
  SET_STRING_ELT(nms, 1, Rf_mkChar("type"));
  SET_STRING_ELT(nms, 2, Rf_mkChar("decltype"));
  SET_VECTOR_ELT(out, 0, name);
  SET_VECTOR_ELT(out, 1, type);
  SET_VECTOR_ELT(out, 2, decl);
  Rf_setAttrib(out, R_NamesSymbol, nms);
  UNPROTECT(5);
  return out;
}

/* -------------------------------------------------- external pointer glue -- */

static SEXP dltr_res_tag = NULL;

static void dltr_res_finalizer(SEXP xp) {
  DoltliteResult *res = (DoltliteResult *) R_ExternalPtrAddr(xp);
  if (res == NULL) return;
  R_ClearExternalPtr(xp);
  /* Reaching the collector while still active means dbClearResult() was never
   * called. DBI asks backends to say so rather than clean up silently. */
  if (res->is_active()) {
    Rf_warning("closing an open result set that was never cleared");
  }
  delete res;
}

SEXP dltr_res_to_sexp(DoltliteResult *res) {
  if (dltr_res_tag == NULL) dltr_res_tag = Rf_install("DOLTLITE_RESULT");
  SEXP xp = PROTECT(R_MakeExternalPtr(res, dltr_res_tag, R_NilValue));
  R_RegisterCFinalizerEx(xp, dltr_res_finalizer, TRUE);
  UNPROTECT(1);
  return xp;
}

DoltliteResult *dltr_res_from_sexp(SEXP res) {
  if (TYPEOF(res) != EXTPTRSXP) {
    throw std::runtime_error("not a doltliter result handle");
  }
  DoltliteResult *r = (DoltliteResult *) R_ExternalPtrAddr(res);
  if (r == NULL) throw std::runtime_error("this result set has been cleared");
  return r;
}

/* ------------------------------------------------------------ .Call layer -- */

extern "C" SEXP C_dltr_send_query(SEXP con, SEXP sql) {
  BEGIN_CPP
  DoltliteConnection *conn = dltr_conn_from_sexp(con);
  conn->check();

  if (TYPEOF(sql) != STRSXP || Rf_length(sql) != 1 ||
      STRING_ELT(sql, 0) == NA_STRING) {
    throw std::runtime_error("the statement must be a single, non-NA string");
  }

  /* DBI permits one active result per connection. Match RSQLite: close the
   * stale one and warn, rather than refusing the new query. */
  if (conn->has_open_result()) {
    Rf_warning("closing the open result set");
    conn->close_open_results();
  }

  std::string text = Rf_translateCharUTF8(STRING_ELT(sql, 0));
  DoltliteResult *res = new DoltliteResult(conn, text);
  return dltr_res_to_sexp(res);
  END_CPP
}

extern "C" SEXP C_dltr_result_bind(SEXP res, SEXP params) {
  BEGIN_CPP
  dltr_res_from_sexp(res)->bind(params);
  return R_NilValue;
  END_CPP
}

extern "C" SEXP C_dltr_result_fetch(SEXP res, SEXP n) {
  BEGIN_CPP
  double want = Rf_asReal(n);
  int lim;
  if (!R_FINITE(want) || want < 0) {
    lim = -1;
  } else if (want > (double) INT_MAX) {
    lim = -1;
  } else {
    lim = (int) want;
  }
  return dltr_res_from_sexp(res)->fetch(lim);
  END_CPP
}

extern "C" SEXP C_dltr_result_clear(SEXP res) {
  BEGIN_CPP
  dltr_res_from_sexp(res)->close();
  return R_NilValue;
  END_CPP
}

extern "C" SEXP C_dltr_result_is_valid(SEXP res) {
  if (TYPEOF(res) != EXTPTRSXP) return Rf_ScalarLogical(FALSE);
  DoltliteResult *r = (DoltliteResult *) R_ExternalPtrAddr(res);
  return Rf_ScalarLogical(r != NULL && r->is_active());
}

extern "C" SEXP C_dltr_result_completed(SEXP res) {
  BEGIN_CPP
  return Rf_ScalarLogical(dltr_res_from_sexp(res)->completed());
  END_CPP
}

extern "C" SEXP C_dltr_result_rows_affected(SEXP res) {
  BEGIN_CPP
  /* Deliberately no bind check: DBI specifies NA_integer_ for a statement
     that has not been bound yet, rather than an error. */
  return Rf_ScalarInteger(dltr_res_from_sexp(res)->rows_affected());
  END_CPP
}

extern "C" SEXP C_dltr_result_rows_fetched(SEXP res) {
  BEGIN_CPP
  return Rf_ScalarReal(dltr_res_from_sexp(res)->rows_fetched());
  END_CPP
}

extern "C" SEXP C_dltr_result_column_info(SEXP res) {
  BEGIN_CPP
  return dltr_res_from_sexp(res)->column_info();
  END_CPP
}

extern "C" SEXP C_dltr_result_statement(SEXP res) {
  BEGIN_CPP
  return Rf_mkString(dltr_res_from_sexp(res)->statement().c_str());
  END_CPP
}

extern "C" SEXP C_dltr_result_parameter_count(SEXP res) {
  BEGIN_CPP
  return Rf_ScalarInteger(dltr_res_from_sexp(res)->parameter_count());
  END_CPP
}
