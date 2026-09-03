/* doltliter: shared declarations for the DoltLite DBI backend.
 *
 * The class layout mirrors RSQLite's SqliteConnection / SqliteResult, because
 * the C surface really is SQLite's own -- only the header, the link target and
 * the version-control SQL differ. What is deliberately *not* borrowed is
 * RSQLite's cpp11/Rcpp dependency: every entry point below is a plain .Call
 * registered from init.c, which keeps the dependency footprint to DBI alone.
 */
#ifndef DOLTLITER_H
#define DOLTLITER_H

#include <doltlite.h>

#include <R.h>
#include <Rinternals.h>

#ifdef __cplusplus

#include <stdexcept>
#include <string>

/* R signals errors with a longjmp, which would walk straight past C++
 * destructors. So each entry point catches everything, copies the message
 * somewhere safe, lets the C++ stack unwind, and only then calls Rf_error.  */
void dltr_stash_error(const char *what);
SEXP dltr_raise_stashed(void);

#define BEGIN_CPP try {

#define END_CPP                                     \
  }                                                 \
  catch (const std::exception &e) {                 \
    dltr_stash_error(e.what());                     \
  }                                                 \
  catch (...) {                                     \
    dltr_stash_error("unknown C++ exception");      \
  }                                                 \
  return dltr_raise_stashed();

/* How a 64-bit INTEGER that will not fit in an R integer is delivered. */
enum BigIntMode {
  BIGINT_INTEGER64 = 0, /* bit64::integer64 (default, matches RSQLite) */
  BIGINT_INTEGER,       /* R integer, NA when out of range */
  BIGINT_NUMERIC,       /* double, lossy beyond 2^53 */
  BIGINT_CHARACTER      /* decimal string, always exact */
};

extern "C" {
#endif /* __cplusplus */

/* --- connection ------------------------------------------------------- */
SEXP C_dltr_connect(SEXP dbname, SEXP flags, SEXP vfs, SEXP bigint,
                    SEXP busy_timeout);
SEXP C_dltr_disconnect(SEXP con);
SEXP C_dltr_is_valid(SEXP con);
SEXP C_dltr_exec(SEXP con, SEXP sql);
SEXP C_dltr_last_insert_rowid(SEXP con);
SEXP C_dltr_changes(SEXP con);
SEXP C_dltr_total_changes(SEXP con);
SEXP C_dltr_set_busy_timeout(SEXP con, SEXP ms);
SEXP C_dltr_interrupt(SEXP con);
SEXP C_dltr_conn_info(SEXP con);
SEXP C_dltr_in_transaction(SEXP con);

/* --- result ----------------------------------------------------------- */
SEXP C_dltr_send_query(SEXP con, SEXP sql);
SEXP C_dltr_result_bind(SEXP res, SEXP params);
SEXP C_dltr_result_fetch(SEXP res, SEXP n);
SEXP C_dltr_result_clear(SEXP res);
SEXP C_dltr_result_is_valid(SEXP res);
SEXP C_dltr_result_completed(SEXP res);
SEXP C_dltr_result_rows_affected(SEXP res);
SEXP C_dltr_result_rows_fetched(SEXP res);
SEXP C_dltr_result_column_info(SEXP res);
SEXP C_dltr_result_statement(SEXP res);
SEXP C_dltr_result_parameter_count(SEXP res);

/* --- library level ---------------------------------------------------- */
SEXP C_dltr_libversion(void);
SEXP C_dltr_engine(void);
SEXP C_dltr_build_info(void);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* DOLTLITER_H */
