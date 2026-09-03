/* doltliter: the connection object. Mirrors RSQLite's SqliteConnection. */
#ifndef DOLTLITE_CONNECTION_H
#define DOLTLITE_CONNECTION_H

#include "doltliter.h"

#include <set>
#include <string>

class DoltliteResult;

class DoltliteConnection {
public:
  DoltliteConnection(const std::string &dbname, int flags, const std::string &vfs,
                     BigIntMode bigint, int busy_timeout_ms);
  ~DoltliteConnection();

  /* Throws if the connection has already been disconnected, so that every
   * caller gets DBI's "invalid connection" error rather than a segfault. */
  sqlite3 *check() const;

  void disconnect();
  bool is_valid() const { return conn_ != NULL; }

  const std::string &dbname() const { return dbname_; }
  BigIntMode bigint() const { return bigint_; }

  /* Results register themselves so that disconnecting can invalidate any that
   * are still reachable from R; otherwise their finalizers would later call
   * sqlite3_finalize() on statements belonging to a freed sqlite3 handle. */
  void register_result(DoltliteResult *res);
  void unregister_result(DoltliteResult *res);

  /* DBI allows one active result per connection. Like RSQLite, sending a new
   * query closes a still-open one and warns rather than refusing outright. */
  void close_open_results();
  bool has_open_result() const;

  /* Raises the current sqlite3 error as a C++ exception. */
  void raise() const;
  void raise(int rc) const;

private:
  DoltliteConnection(const DoltliteConnection &);
  DoltliteConnection &operator=(const DoltliteConnection &);

  sqlite3 *conn_;
  std::string dbname_;
  BigIntMode bigint_;
  std::set<DoltliteResult *> results_;
};

/* External-pointer plumbing shared with doltlite_result.cpp. */
DoltliteConnection *dltr_conn_from_sexp(SEXP con);
SEXP dltr_conn_to_sexp(DoltliteConnection *conn);

#endif /* DOLTLITE_CONNECTION_H */
