# Shared machinery for calling DoltLite's version-control surface.
#
# That surface comes in two shapes, and conflating them is the easiest way to
# get this wrong:
#
#   * scalar SQL functions  -- dolt_commit, dolt_branch, dolt_checkout,
#     dolt_merge, dolt_config, active_branch ... called as SELECT dolt_x(...)
#   * virtual tables and table-valued functions -- dolt_log, dolt_status,
#     dolt_diff, dolt_diff_<table>, dolt_history_<table>, dolt_blame_<table>,
#     dolt_diff_stat, dolt_patch ... called as SELECT * FROM dolt_x(...)
#
# Arguments are always passed as bound `?` parameters, never interpolated.
# Binding works for both shapes (verified against DoltLite 0.50.3), so a commit
# message containing quotes or semicolons is simply a value, and there is no
# injection surface to reason about. The function *name* cannot be
# parameterised, so it is validated instead.

# A Dolt function or table name. Anything outside this shape is either a typo
# or an attempt to smuggle SQL through a name, and both deserve an error.
dolt_check_name <- function(name, what = "name") {
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
      !nzchar(name)) {
    stop("`", what, "` must be a single, non-empty string", call. = FALSE)
  }
  if (!grepl("^[A-Za-z_][A-Za-z0-9_]*$", name)) {
    stop("invalid ", what, " '", name, "': expected a plain SQL identifier",
         call. = FALSE)
  }
  name
}

# Drop NULLs, flatten, and insist everything left is an atomic scalar. Dolt
# functions are variadic and take flag-style arguments ('-Am', '--author'),
# so building the list is easier than a fixed signature per verb.
dolt_args <- function(...) {
  args <- list(...)
  args <- args[!vapply(args, is.null, logical(1))]
  args <- unlist(args, use.names = FALSE, recursive = TRUE)
  if (is.null(args)) return(character())
  if (anyNA(args)) stop("Dolt arguments must not be NA", call. = FALSE)
  as.character(args)
}

dolt_placeholders <- function(n) {
  if (n == 0L) return("")
  paste(rep("?", n), collapse = ", ")
}

dolt_require_conn <- function(con) {
  if (!methods::is(con, "DoltliteConnection")) {
    stop("`con` must be a DoltliteConnection", call. = FALSE)
  }
  if (!dbIsValid(con)) stop("invalid or closed connection", call. = FALSE)
  invisible(con)
}

# Version control needs a DoltLite-format database. An anonymous temporary
# database (dbname = "") is created in SQLite's original B-tree format, where
# none of these functions exist; say so plainly rather than letting SQLite
# report "no such function".
dolt_require_versioned <- function(con, fn) {
  engine <- tryCatch(
    dbGetQuery(con, "SELECT doltlite_engine() AS e")$e[[1L]],
    error = function(e) NA_character_
  )
  if (!identical(engine, "prolly")) {
    stop(sprintf(
      "%s() needs a DoltLite-format database, but this connection reports engine '%s'.\nAnonymous temporary databases (dbname = \"\") and attached stock SQLite files are not version controlled; connect to a file path instead.",
      fn, if (is.na(engine)) "unknown" else engine
    ), call. = FALSE)
  }
  invisible(TRUE)
}

#' Call a Dolt scalar SQL function
#'
#' Escape hatch for a version-control function this package does not wrap
#' yet. Arguments are bound as parameters, so they are always treated as
#' values.
#'
#' @param con a `DoltliteConnection`.
#' @param fn the function name, e.g. `"dolt_commit"`.
#' @param ... arguments, passed through in order.
#' @return The function's single return value.
#' @export
#' @examples
#' con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
#' dolt_scalar(con, "dolt_config", "user.name", "Ada")
#' DBI::dbDisconnect(con)
dolt_scalar <- function(con, fn, ...) {
  dolt_require_conn(con)
  dolt_check_name(fn, "function name")
  args <- dolt_args(...)
  sql <- paste0("SELECT ", fn, "(", dolt_placeholders(length(args)), ")")
  out <- dbGetQuery(con, sql, params = if (length(args)) as.list(args) else NULL)
  if (nrow(out) == 0L || ncol(out) == 0L) return(invisible(NULL))
  out[[1L]][[1L]]
}

#' Query a Dolt virtual table or table-valued function
#'
#' Escape hatch for a version-control relation this package does not wrap yet.
#'
#' @param con a `DoltliteConnection`.
#' @param fn the relation name, e.g. `"dolt_log"` or `"dolt_diff_users"`.
#' @param ... arguments. With none, the relation is read as a plain virtual
#'   table; with arguments, as a table-valued function.
#' @return A data frame.
#' @export
dolt_table <- function(con, fn, ...) {
  dolt_require_conn(con)
  dolt_check_name(fn, "relation name")
  args <- dolt_args(...)
  sql <- if (length(args) == 0L) {
    paste0("SELECT * FROM ", fn)
  } else {
    paste0("SELECT * FROM ", fn, "(", dolt_placeholders(length(args)), ")")
  }
  dbGetQuery(con, sql, params = if (length(args)) as.list(args) else NULL)
}

# Per-table relations (dolt_diff_<t>, dolt_history_<t>, ...) put the table name
# into the *relation* name, so it is validated as an identifier rather than
# bound.
dolt_table_suffixed <- function(con, prefix, table, ...) {
  dolt_check_name(table, "table")
  dolt_table(con, paste0(prefix, table), ...)
}
