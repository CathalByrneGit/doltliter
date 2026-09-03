#' Commit history
#'
#' @param con a `DoltliteConnection`.
#' @param ref optionally a branch, tag or revision range, e.g. `"feature"`,
#'   `"main..feature"`. Omit for the current branch's history.
#' @return A data frame with columns `commit_hash`, `committer`, `email`,
#'   `date` and `message`, newest first.
#' @export
#' @examples
#' con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
#' dolt_config(con, user.name = "Ada", user.email = "ada@example.com")
#' DBI::dbWriteTable(con, "t", data.frame(x = 1))
#' dolt_commit(con, "init")
#' dolt_log(con)[, c("committer", "message")]
#' DBI::dbDisconnect(con)
dolt_log <- function(con, ref = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_log")
  dolt_table(con, "dolt_log", ref)
}

#' Which tables changed, per commit
#'
#' @param con a `DoltliteConnection`.
#' @param table optionally restrict to one table.
#' @return A data frame with columns `commit_hash`, `committer`, `email`,
#'   `date`, `message`, `data_change`, `schema_change` and `table_name`. The
#'   pseudo-commit `WORKING` covers uncommitted changes.
#' @export
dolt_diff <- function(con, table = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_diff")
  if (is.null(table)) return(dolt_table(con, "dolt_diff"))
  dbGetQuery(con, "SELECT * FROM dolt_diff WHERE table_name = ?",
             params = list(table))
}

#' Row-level differences for one table
#'
#' Wraps DoltLite's per-table `dolt_diff_<table>` relation. Columns come in
#' `from_`/`to_` pairs plus commit metadata and a `diff_type`.
#'
#' @param con a `DoltliteConnection`.
#' @param table the table name.
#' @param from,to endpoints: a branch, tag, commit hash, `HEAD~1`, `WORKING`,
#'   and so on. Give both for a two-point diff. Give neither to get the
#'   table's whole per-commit row history.
#' @param range alternatively a range string: `"main..feature"` for the two
#'   endpoints, or `"main...feature"` for merge-base to right endpoint.
#' @return A data frame.
#' @export
#' @examples
#' con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
#' dolt_config(con, user.name = "Ada", user.email = "ada@example.com")
#' DBI::dbWriteTable(con, "t", data.frame(id = 1:2, v = c(10, 20)))
#' dolt_commit(con, "init")
#' DBI::dbExecute(con, "UPDATE t SET v = 99 WHERE id = 1")
#' dolt_table_diff(con, "t", from = "HEAD", to = "WORKING")$diff_type
#' DBI::dbDisconnect(con)
dolt_table_diff <- function(con, table, from = NULL, to = NULL, range = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_table_diff")

  if (!is.null(range)) {
    if (!is.null(from) || !is.null(to)) {
      stop("supply either `range`, or `from`/`to`, not both", call. = FALSE)
    }
    return(dolt_table_suffixed(con, "dolt_diff_", table, range))
  }
  if (is.null(from) && is.null(to)) {
    return(dolt_table_suffixed(con, "dolt_diff_", table))
  }
  if (is.null(from) || is.null(to)) {
    stop("supply both `from` and `to`, or neither", call. = FALSE)
  }
  dolt_table_suffixed(con, "dolt_diff_", table, from, to)
}

#' Diff statistics and summaries
#'
#' @param con a `DoltliteConnection`.
#' @param from,to endpoint refs.
#' @param table optionally restrict to one table.
#' @return A data frame. `dolt_diff_stat()` gives row and cell counts,
#'   `dolt_diff_summary()` gives per-table added / dropped / renamed /
#'   modified, and `dolt_schema_diff()` gives schema-level changes.
#' @export
dolt_diff_stat <- function(con, from, to, table = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_diff_stat")
  dolt_table(con, "dolt_diff_stat", from, to, table)
}

#' @rdname dolt_diff_stat
#' @export
dolt_diff_summary <- function(con, from, to, table = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_diff_summary")
  dolt_table(con, "dolt_diff_summary", from, to, table)
}

#' @rdname dolt_diff_stat
#' @export
dolt_schema_diff <- function(con, from, to, table = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_schema_diff")
  dolt_table(con, "dolt_schema_diff", from, to, table)
}

#' Executable patch between two refs
#'
#' @param con a `DoltliteConnection`.
#' @param from,to endpoint refs. `from` may instead be a range string such as
#'   `"v1.0..v2.0"`, in which case leave `to` empty.
#' @param table optionally restrict to one table.
#' @return A data frame of ordered SQLite statements, with `statement_order`
#'   and `diff_type` columns.
#' @export
dolt_patch <- function(con, from, to = NULL, table = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_patch")
  dolt_table(con, "dolt_patch", from, to, table)
}

#' Every version of every row in a table
#'
#' @param con a `DoltliteConnection`.
#' @param table the table name.
#' @param ref optionally start the walk from another branch, tag or commit.
#' @return A data frame: the table's columns plus commit metadata.
#' @export
dolt_history <- function(con, table, ref = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_history")
  dolt_table_suffixed(con, "dolt_history_", table, ref)
}

#' A table as it existed at a given revision
#'
#' @param con a `DoltliteConnection`.
#' @param table the table name.
#' @param ref a commit hash, branch or tag.
#' @return A data frame with the table's own columns.
#' @export
dolt_at <- function(con, table, ref) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_at")
  dolt_table_suffixed(con, "dolt_at_", table, ref)
}

#' Which commit last set each row
#'
#' A first-parent walk from `HEAD`. Schema-only changes such as
#' `ALTER TABLE ADD COLUMN` do not update blame.
#'
#' @param con a `DoltliteConnection`.
#' @param table the table name.
#' @return A data frame with the primary key plus `commit`, `commit_date`,
#'   `committer`, `email` and `message`.
#' @export
dolt_blame <- function(con, table) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_blame")
  dolt_table_suffixed(con, "dolt_blame_", table)
}

#' Row-level working and staged edits
#'
#' Set the `staged` column with an ordinary `UPDATE` to stage or unstage
#' individual rows.
#'
#' @param con a `DoltliteConnection`.
#' @param table the table name.
#' @return A data frame.
#' @export
dolt_workspace <- function(con, table) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_workspace")
  dolt_table_suffixed(con, "dolt_workspace_", table)
}

#' Versioned views and triggers
#'
#' @param con a `DoltliteConnection`.
#' @return A data frame with `type`, `name`, `fragment`, `extra` and
#'   `sql_mode`. Ordinary tables and indexes are not listed here; use
#'   `sqlite_schema` or [dolt_schema_diff()] for the full schema surface.
#' @export
dolt_schemas <- function(con) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_schemas")
  dolt_table(con, "dolt_schemas")
}
