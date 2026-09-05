/* Runtime probe: does DoltLite's prolly store actually work under wasm?
   Goes past the configure probe deliberately -- that one only opens :memory:,
   which DoltLite serves with the 'orig' B-tree engine. Version control only
   exists on a file-backed database, so that is what we exercise here. */
#include <doltlite.h>
#include <stdio.h>
#include <string.h>

static sqlite3 *db;
static int fails = 0;

static void check(const char *label, const char *sql, const char *want) {
  sqlite3_stmt *st;
  const unsigned char *got;
  if (sqlite3_prepare_v2(db, sql, -1, &st, 0) != SQLITE_OK) {
    printf("FAIL %-22s prepare: %s\n", label, sqlite3_errmsg(db));
    fails++;
    return;
  }
  if (sqlite3_step(st) != SQLITE_ROW) {
    printf("FAIL %-22s step: %s\n", label, sqlite3_errmsg(db));
    fails++;
    sqlite3_finalize(st);
    return;
  }
  got = sqlite3_column_text(st, 0);
  if (want && strcmp((const char *) got, want) != 0)  {
    printf("FAIL %-22s got '%s' want '%s'\n", label, got, want);
    fails++;
  } else {
    printf("ok   %-22s %s\n", label, got ? (const char *) got : "(null)");
  }
  sqlite3_finalize(st);
}

static void exec(const char *label, const char *sql) {
  char *err = 0;
  if (sqlite3_exec(db, sql, 0, 0, &err) != SQLITE_OK) {
    printf("FAIL %-22s %s\n", label, err ? err : "?");
    sqlite3_free(err);
    fails++;
  } else {
    printf("ok   %-22s\n", label);
  }
}

int main(void) {
  if (sqlite3_open("/work/spike.db", &db) != SQLITE_OK) {
    printf("FAIL open: %s\n", sqlite3_errmsg(db));
    return 1;
  }
  check("engine",        "SELECT doltlite_engine()", "prolly");
  check("version",       "SELECT dolt_version()", NULL);
  exec ("create table",  "CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)");
  exec ("insert",        "INSERT INTO t VALUES (1,'alpha'),(2,'beta')");
  check("config name",   "SELECT dolt_config('user.name','Ada Lovelace')", NULL);
  check("config email",  "SELECT dolt_config('user.email','ada@example.com')", NULL);
  check("add",           "SELECT dolt_add('-A')", NULL);
  check("commit",        "SELECT dolt_commit('-Am','first commit')", NULL);
  check("log count",     "SELECT count(*) FROM dolt_log()", NULL);
  check("branch",        "SELECT dolt_branch('experiment')", NULL);
  check("checkout",      "SELECT dolt_checkout('experiment')", NULL);
  exec ("update",        "UPDATE t SET v='BETA' WHERE id=2");
  check("add 2",         "SELECT dolt_add('-A')", NULL);
  check("commit 2",      "SELECT dolt_commit('-Am','uppercase beta')", NULL);
  check("diff rows",     "SELECT count(*) FROM dolt_diff", NULL);
  check("row diff",      "SELECT diff_type FROM dolt_diff_t "
                         "WHERE to_commit='WORKING' OR from_commit='main' LIMIT 1", NULL);
  check("active branch", "SELECT active_branch()", "experiment");
  check("hashof db",     "SELECT dolt_hashof_db()", NULL);
  sqlite3_close(db);
  printf("\n%s (%d failure%s)\n", fails ? "FAILURES" : "ALL PASSED",
         fails, fails == 1 ? "" : "s");
  return fails ? 1 : 0;
}
