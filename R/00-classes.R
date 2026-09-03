# All S4 class definitions live here, and DESCRIPTION's Collate: field puts
# this file first. Defining a class in the same file as the methods that
# mention another class makes load order load-bearing, which is exactly the
# kind of breakage that only shows up on someone else's machine.

#' @importFrom methods new setClass setMethod setValidity slot validObject show
#' @importClassesFrom DBI DBIDriver DBIConnection DBIResult
#' @importFrom DBI dbConnect dbDisconnect dbIsValid dbGetInfo dbSendQuery
#'   dbSendStatement dbFetch dbClearResult dbHasCompleted dbColumnInfo
#'   dbGetRowCount dbGetRowsAffected dbGetStatement dbBind dbGetQuery dbExecute
#'   dbListTables dbExistsTable dbListFields dbReadTable dbWriteTable
#'   dbRemoveTable dbBegin dbCommit dbRollback dbDataType dbQuoteString
#'   dbQuoteIdentifier dbUnloadDriver dbAppendTable dbCreateTable
NULL

#' DoltLite driver class
#'
#' Returned by [Doltlite()] and passed to [DBI::dbConnect()].
#'
#' @keywords internal
#' @export
setClass("DoltliteDriver", contains = "DBIDriver")

#' DoltLite connection class
#'
#' @slot ptr external pointer to the C connection object.
#' @slot dbname the database path, without any branch suffix.
#' @slot branch the branch requested at connect time, or `NA`.
#' @slot bigint how out-of-range 64-bit integers are returned.
#' @slot state an environment holding mutable per-connection state, chiefly
#'   whether a transaction is open. S4 slots are copy-on-modify, so mutable
#'   bookkeeping has to live in a reference object.
#'
#' @keywords internal
#' @export
setClass("DoltliteConnection",
  contains = "DBIConnection",
  slots = list(
    ptr = "externalptr",
    dbname = "character",
    branch = "character",
    bigint = "character",
    state = "environment"
  )
)

#' DoltLite result class
#'
#' @slot ptr external pointer to the C result object.
#' @slot conn the connection that produced this result.
#' @slot sql the statement text.
#' @slot is_statement whether the statement returns no columns.
#'
#' @keywords internal
#' @export
setClass("DoltliteResult",
  contains = "DBIResult",
  slots = list(
    ptr = "externalptr",
    conn = "DoltliteConnection",
    sql = "character",
    is_statement = "logical"
  )
)

# ---------------------------------------------------------------- open flags --

#' Database open flags
#'
#' Passed as `flags` to [DBI::dbConnect()]. These are SQLite's
#' `SQLITE_OPEN_*` values.
#'
#' @export
DOLTLITE_RO <- 1L

#' @rdname DOLTLITE_RO
#' @export
DOLTLITE_RW <- 2L

#' @rdname DOLTLITE_RO
#' @export
DOLTLITE_RWC <- 6L
