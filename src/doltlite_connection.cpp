#include "doltlite_connection.h"
#include "doltlite_result.h"

#include <cstdio>
#include <cstring>
#include <vector>

/* ---------------------------------------------------------------- errors -- */

/* A fixed buffer, not a std::string: this is written from inside a catch block
 * and read after the C++ stack has unwound, so it must not itself allocate. */
static char dltr_error_buf[2048];
static int dltr_error_set = 0;

void dltr_stash_error(const char *what) {
  if (what == NULL) what = "unknown error";
  std::snprintf(dltr_error_buf, sizeof dltr_error_buf, "%s", what);
  dltr_error_set = 1;
}

SEXP dltr_raise_stashed(void) {
  if (dltr_error_set) {
    dltr_error_set = 0;
    Rf_error("%s", dltr_error_buf);
  }
  return R_NilValue;
}

/* ------------------------------------------------------------ connection -- */

DoltliteConnection::DoltliteConnection(const std::string &dbname, int flags,
                                       const std::string &vfs, BigIntMode bigint,
                                       int busy_timeout_ms)
    : conn_(NULL), dbname_(dbname), bigint_(bigint) {
  int rc = sqlite3_open_v2(dbname.c_str(), &conn_, flags,
                           vfs.empty() ? NULL : vfs.c_str());
  if (rc != SQLITE_OK) {
    /* sqlite3_open_v2 hands back a handle even on failure so that the error
     * message can be read off it; close it before throwing. */
    std::string msg = conn_ ? sqlite3_errmsg(conn_) : sqlite3_errstr(rc);
    if (conn_) {
      sqlite3_close_v2(conn_);
      conn_ = NULL;
    }
    if (rc == SQLITE_NOTADB) {
      /* Overwhelmingly the DoltLite meaning: readers require an exact
       * chunk-store format match and refuse anything else outright. */
      throw std::runtime_error(
          "could not open '" + dbname + "': " + msg +
          "\nThis usually means the file was written by a DoltLite release with a"
          " different on-disk format version, or is not a database at all.");
    }
    throw std::runtime_error("could not connect to '" + dbname + "': " + msg);
  }

  /* One durable writer at a time: a peer holding the graph lock makes us
   * SQLITE_BUSY, so wait rather than failing instantly. */
  if (busy_timeout_ms > 0) sqlite3_busy_timeout(conn_, busy_timeout_ms);

  sqlite3_extended_result_codes(conn_, 1);

  /* SQLite treats a double-quoted identifier that resolves to nothing as a
   * string literal. That turns a typo'd column name into a silently wrong
   * query, so turn it off in both DML and DDL, as modern SQLite advises. */
#ifdef SQLITE_DBCONFIG_DQS_DML
  sqlite3_db_config(conn_, SQLITE_DBCONFIG_DQS_DML, 0, (int *) 0);
#endif
#ifdef SQLITE_DBCONFIG_DQS_DDL
  sqlite3_db_config(conn_, SQLITE_DBCONFIG_DQS_DDL, 0, (int *) 0);
#endif
}

DoltliteConnection::~DoltliteConnection() {
  try {
    disconnect();
  } catch (...) {
    /* A destructor must not throw; a failed close leaks at worst. */
  }
}

sqlite3 *DoltliteConnection::check() const {
  if (conn_ == NULL) throw std::runtime_error("invalid or closed connection");
  return conn_;
}

void DoltliteConnection::disconnect() {
  if (conn_ == NULL) return;

  /* Tell every live result that its statement is about to become invalid.
   * Copy first: notify_connection_closed() calls back into
   * unregister_result() and would otherwise invalidate the iterator. */
  std::vector<DoltliteResult *> live(results_.begin(), results_.end());
  results_.clear();
  for (size_t i = 0; i < live.size(); ++i) {
    live[i]->notify_connection_closed();
  }

  sqlite3 *c = conn_;
  conn_ = NULL;
  sqlite3_close_v2(c);
}

void DoltliteConnection::register_result(DoltliteResult *res) {
  results_.insert(res);
}

void DoltliteConnection::unregister_result(DoltliteResult *res) {
  results_.erase(res);
}

bool DoltliteConnection::has_open_result() const {
  for (std::set<DoltliteResult *>::const_iterator it = results_.begin();
       it != results_.end(); ++it) {
    if ((*it)->is_active()) return true;
  }
  return false;
}

void DoltliteConnection::close_open_results() {
  std::vector<DoltliteResult *> live(results_.begin(), results_.end());
  for (size_t i = 0; i < live.size(); ++i) {
    if (live[i]->is_active()) live[i]->close();
  }
}

void DoltliteConnection::raise() const {
  throw std::runtime_error(conn_ ? sqlite3_errmsg(conn_) : "invalid connection");
}

void DoltliteConnection::raise(int rc) const {
  std::string msg = conn_ ? sqlite3_errmsg(conn_) : sqlite3_errstr(rc);
  throw std::runtime_error(msg);
}

/* -------------------------------------------------- external pointer glue -- */

static SEXP dltr_conn_tag = NULL;

static void dltr_conn_finalizer(SEXP xp) {
  DoltliteConnection *conn = (DoltliteConnection *) R_ExternalPtrAddr(xp);
  if (conn == NULL) return;
  R_ClearExternalPtr(xp);
  delete conn;
}

SEXP dltr_conn_to_sexp(DoltliteConnection *conn) {
  if (dltr_conn_tag == NULL) {
    dltr_conn_tag = Rf_install("DOLTLITE_CONNECTION");
  }
  SEXP xp = PROTECT(R_MakeExternalPtr(conn, dltr_conn_tag, R_NilValue));
  R_RegisterCFinalizerEx(xp, dltr_conn_finalizer, TRUE);
  UNPROTECT(1);
  return xp;
}

DoltliteConnection *dltr_conn_from_sexp(SEXP con) {
  if (TYPEOF(con) != EXTPTRSXP) {
    throw std::runtime_error("not a doltliter connection handle");
  }
  DoltliteConnection *conn = (DoltliteConnection *) R_ExternalPtrAddr(con);
  if (conn == NULL) {
    throw std::runtime_error(
        "this connection handle is no longer valid; it belongs to a session "
        "that has ended");
  }
  return conn;
}

/* ------------------------------------------------------------ .Call layer -- */

static std::string dltr_str(SEXP x, const char *what) {
  if (TYPEOF(x) != STRSXP || Rf_length(x) != 1) {
    throw std::runtime_error(std::string(what) + " must be a single string");
  }
  SEXP e = STRING_ELT(x, 0);
  if (e == NA_STRING) {
    throw std::runtime_error(std::string(what) + " must not be NA");
  }
  return std::string(Rf_translateCharUTF8(e));
}

static int dltr_int(SEXP x, const char *what) {
  if (Rf_length(x) != 1) {
    throw std::runtime_error(std::string(what) + " must be a single value");
  }
  int v = Rf_asInteger(x);
  if (v == NA_INTEGER) {
    throw std::runtime_error(std::string(what) + " must not be NA");
  }
  return v;
}

extern "C" SEXP C_dltr_connect(SEXP dbname, SEXP flags, SEXP vfs, SEXP bigint,
                               SEXP busy_timeout) {
  BEGIN_CPP
  std::string path = dltr_str(dbname, "dbname");
  std::string vfs_name;
  if (TYPEOF(vfs) == STRSXP && Rf_length(vfs) == 1 &&
      STRING_ELT(vfs, 0) != NA_STRING) {
    vfs_name = Rf_translateCharUTF8(STRING_ELT(vfs, 0));
  }
  BigIntMode mode = (BigIntMode) dltr_int(bigint, "bigint");
  DoltliteConnection *conn = new DoltliteConnection(
      path, dltr_int(flags, "flags"), vfs_name, mode,
      dltr_int(busy_timeout, "busy_timeout"));
  return dltr_conn_to_sexp(conn);
  END_CPP
}

extern "C" SEXP C_dltr_disconnect(SEXP con) {
  BEGIN_CPP
  DoltliteConnection *conn = dltr_conn_from_sexp(con);
  conn->disconnect();
  return R_NilValue;
  END_CPP
}

extern "C" SEXP C_dltr_is_valid(SEXP con) {
  /* Never throws: dbIsValid() must answer FALSE rather than error, including
   * for a handle whose external pointer was cleared by session reload. */
  if (TYPEOF(con) != EXTPTRSXP) return Rf_ScalarLogical(FALSE);
  DoltliteConnection *conn = (DoltliteConnection *) R_ExternalPtrAddr(con);
  return Rf_ScalarLogical(conn != NULL && conn->is_valid());
}

extern "C" SEXP C_dltr_exec(SEXP con, SEXP sql) {
  BEGIN_CPP
  DoltliteConnection *conn = dltr_conn_from_sexp(con);
  std::string text = dltr_str(sql, "statement");
  char *errmsg = NULL;
  int rc = sqlite3_exec(conn->check(), text.c_str(), NULL, NULL, &errmsg);
  if (rc != SQLITE_OK) {
    std::string msg = errmsg ? errmsg : sqlite3_errstr(rc);
    if (errmsg) sqlite3_free(errmsg);
    throw std::runtime_error(msg);
  }
  if (errmsg) sqlite3_free(errmsg);
  return R_NilValue;
  END_CPP
}

extern "C" SEXP C_dltr_last_insert_rowid(SEXP con) {
  BEGIN_CPP
  DoltliteConnection *conn = dltr_conn_from_sexp(con);
  return Rf_ScalarReal((double) sqlite3_last_insert_rowid(conn->check()));
  END_CPP
}

extern "C" SEXP C_dltr_changes(SEXP con) {
  BEGIN_CPP
  DoltliteConnection *conn = dltr_conn_from_sexp(con);
  return Rf_ScalarInteger(sqlite3_changes(conn->check()));
  END_CPP
}

extern "C" SEXP C_dltr_total_changes(SEXP con) {
  BEGIN_CPP
  DoltliteConnection *conn = dltr_conn_from_sexp(con);
  return Rf_ScalarInteger(sqlite3_total_changes(conn->check()));
  END_CPP
}

extern "C" SEXP C_dltr_set_busy_timeout(SEXP con, SEXP ms) {
  BEGIN_CPP
  DoltliteConnection *conn = dltr_conn_from_sexp(con);
  sqlite3_busy_timeout(conn->check(), dltr_int(ms, "ms"));
  return R_NilValue;
  END_CPP
}

extern "C" SEXP C_dltr_interrupt(SEXP con) {
  BEGIN_CPP
  DoltliteConnection *conn = dltr_conn_from_sexp(con);
  sqlite3_interrupt(conn->check());
  return R_NilValue;
  END_CPP
}

/* Ask SQLite rather than tracking a flag in R. DoltLite's dolt_commit() ends
 * the enclosing SQL transaction as a side effect, so any bookkeeping we kept
 * ourselves would silently go stale. */
extern "C" SEXP C_dltr_in_transaction(SEXP con) {
  BEGIN_CPP
  DoltliteConnection *conn = dltr_conn_from_sexp(con);
  return Rf_ScalarLogical(sqlite3_get_autocommit(conn->check()) == 0);
  END_CPP
}

extern "C" SEXP C_dltr_conn_info(SEXP con) {
  BEGIN_CPP
  DoltliteConnection *conn = dltr_conn_from_sexp(con);
  sqlite3 *db = conn->check();

  const char *names[] = {"dbname", "has_open_result", "readonly", NULL};
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 3));
  SEXP nm = PROTECT(Rf_allocVector(STRSXP, 3));
  for (int i = 0; names[i] != NULL; ++i) {
    SET_STRING_ELT(nm, i, Rf_mkChar(names[i]));
  }
  Rf_setAttrib(out, R_NamesSymbol, nm);

  SET_VECTOR_ELT(out, 0, Rf_mkString(conn->dbname().c_str()));
  SET_VECTOR_ELT(out, 1, Rf_ScalarLogical(conn->has_open_result()));
  SET_VECTOR_ELT(out, 2,
                 Rf_ScalarLogical(sqlite3_db_readonly(db, "main") == 1));
  UNPROTECT(2);
  return out;
  END_CPP
}

/* ----------------------------------------------------------- library info -- */

extern "C" SEXP C_dltr_libversion(void) {
  return Rf_mkString(sqlite3_libversion());
}

extern "C" SEXP C_dltr_engine(void) {
  /* doltlite_engine() is a SQL function, so it needs a scratch connection.
   * Unlike dolt_version() it is reliable on every build path, including the
   * vendored amalgamation. */
  sqlite3 *db = NULL;
  sqlite3_stmt *st = NULL;
  SEXP out = R_NilValue;
  if (sqlite3_open(":memory:", &db) == SQLITE_OK &&
      sqlite3_prepare_v2(db, "SELECT doltlite_engine()", -1, &st, 0) == SQLITE_OK &&
      sqlite3_step(st) == SQLITE_ROW) {
    const unsigned char *t = sqlite3_column_text(st, 0);
    out = Rf_mkString(t ? (const char *) t : "");
  } else {
    out = Rf_mkString("");
  }
  if (st) sqlite3_finalize(st);
  if (db) sqlite3_close_v2(db);
  return out;
}

extern "C" SEXP C_dltr_build_info(void) {
  SEXP out = PROTECT(Rf_allocVector(STRSXP, 3));
  SEXP nm = PROTECT(Rf_allocVector(STRSXP, 3));
  SET_STRING_ELT(nm, 0, Rf_mkChar("sqlite_version"));
  SET_STRING_ELT(nm, 1, Rf_mkChar("sqlite_sourceid"));
  SET_STRING_ELT(nm, 2, Rf_mkChar("threadsafe"));
  SET_STRING_ELT(out, 0, Rf_mkChar(sqlite3_libversion()));
  SET_STRING_ELT(out, 1, Rf_mkChar(sqlite3_sourceid()));
  {
    char buf[32];
    std::snprintf(buf, sizeof buf, "%d", sqlite3_threadsafe());
    SET_STRING_ELT(out, 2, Rf_mkChar(buf));
  }
  Rf_setAttrib(out, R_NamesSymbol, nm);
  UNPROTECT(2);
  return out;
}
