/* doltliter: the result object. Mirrors RSQLite's SqliteResult. */
#ifndef DOLTLITE_RESULT_H
#define DOLTLITE_RESULT_H

#include "doltliter.h"

#include <string>
#include <vector>

class DoltliteConnection;

/* The R type a column will be materialised as. Starts from the declared type
 * where SQLite gives us one and is promoted as values arrive, because an
 * expression column has no declared type at all and a column with NUMERIC
 * affinity can legitimately yield integers, doubles and text in one result. */
enum DType {
  DT_UNKNOWN = 0,
  DT_LGL,   /* only ever produced by an all-NULL column */
  DT_INT,
  DT_INT64,
  DT_REAL,
  DT_TEXT,
  DT_BLOB
};

/* One buffered cell. Values are collected here and turned into R vectors once
 * the whole fetch is done and the column type has settled. Doing it this way
 * costs a second copy but removes every in-place vector promotion, which is
 * where a backend of this shape usually goes wrong. */
struct Cell {
  int type; /* SQLITE_INTEGER / _FLOAT / _TEXT / _BLOB / _NULL */
  sqlite3_int64 i;
  double d;
  std::string s; /* text, and blob bytes */

  Cell() : type(SQLITE_NULL), i(0), d(0) {}
};

class DoltliteResult {
public:
  DoltliteResult(DoltliteConnection *conn, const std::string &sql);
  ~DoltliteResult();

  void bind(SEXP params);
  SEXP fetch(int n);
  SEXP column_info();

  void close();
  void notify_connection_closed();

  bool is_active() const { return stmt_ != NULL; }
  bool completed() const { return completed_; }
  /* A SELECT affects no rows. sqlite3_changes() would report whatever the
   * last DML statement on this connection did, which is not ours to claim. */
  int rows_affected() const { return ncol_ > 0 ? 0 : rows_affected_; }
  double rows_fetched() const { return (double) rows_fetched_; }
  int parameter_count() const;
  void check_bound() const { require_bound(); }
  const std::string &statement() const { return sql_; }

private:
  DoltliteResult(const DoltliteResult &);
  DoltliteResult &operator=(const DoltliteResult &);

  void require_active() const;
  void require_bound() const;
  void step_once();
  void init_columns();
  void bind_one(int idx, SEXP col, int row);
  void bind_set(R_xlen_t row);
  void release_params();
  void update_type(int j);
  void infer_types();
  void collect_row();
  SEXP materialise(int nrow);

  DoltliteConnection *conn_; /* not owned; NULL once the connection closed */
  sqlite3_stmt *stmt_;
  std::string sql_;

  int ncol_;
  std::vector<std::string> names_;
  std::vector<std::string> decltypes_;
  std::vector<DType> types_;
  std::vector<std::vector<Cell> > buf_;

  bool completed_;   /* no more rows */
  bool bound_;       /* parameters have been bound at least once */
  bool needs_bind_;  /* the statement carries parameters */
  bool have_row_;    /* a stepped-but-unconsumed row is waiting */
  int rows_affected_;
  sqlite3_int64 rows_fetched_;
  BigIntMode bigint_;

  /* Parameter sets. DBI lets a query be bound to several sets at once and
   * returns the concatenation, so the values have to outlive bind(); the list
   * is kept alive with R_PreserveObject. */
  SEXP params_;
  std::vector<int> param_index_;
  R_xlen_t nsets_;
  R_xlen_t cur_set_;
};

DoltliteResult *dltr_res_from_sexp(SEXP res);
SEXP dltr_res_to_sexp(DoltliteResult *res);

#endif /* DOLTLITE_RESULT_H */
