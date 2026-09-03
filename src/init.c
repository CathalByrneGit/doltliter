/* doltliter: .Call registration.
 *
 * Plain C, and plain .Call throughout: the C++ in doltlite_connection.cpp and
 * doltlite_result.cpp exposes an extern "C" surface, so the package needs
 * neither Rcpp nor cpp11 and depends only on DBI at the R level.
 */
#include "doltliter.h"

#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

#define CALLDEF(name, n) {#name, (DL_FUNC) &name, n}

static const R_CallMethodDef CallEntries[] = {
    /* connection */
    CALLDEF(C_dltr_connect, 5),
    CALLDEF(C_dltr_disconnect, 1),
    CALLDEF(C_dltr_is_valid, 1),
    CALLDEF(C_dltr_exec, 2),
    CALLDEF(C_dltr_last_insert_rowid, 1),
    CALLDEF(C_dltr_changes, 1),
    CALLDEF(C_dltr_total_changes, 1),
    CALLDEF(C_dltr_set_busy_timeout, 2),
    CALLDEF(C_dltr_interrupt, 1),
    CALLDEF(C_dltr_conn_info, 1),
    CALLDEF(C_dltr_in_transaction, 1),

    /* result */
    CALLDEF(C_dltr_send_query, 2),
    CALLDEF(C_dltr_result_bind, 2),
    CALLDEF(C_dltr_result_fetch, 2),
    CALLDEF(C_dltr_result_clear, 1),
    CALLDEF(C_dltr_result_is_valid, 1),
    CALLDEF(C_dltr_result_completed, 1),
    CALLDEF(C_dltr_result_rows_affected, 1),
    CALLDEF(C_dltr_result_rows_fetched, 1),
    CALLDEF(C_dltr_result_column_info, 1),
    CALLDEF(C_dltr_result_statement, 1),
    CALLDEF(C_dltr_result_parameter_count, 1),

    /* library level */
    CALLDEF(C_dltr_libversion, 0),
    CALLDEF(C_dltr_engine, 0),
    CALLDEF(C_dltr_build_info, 0),

    {NULL, NULL, 0}};

void attribute_visible R_init_doltliter(DllInfo *dll) {
  R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
