# dplyr / dbplyr integration.
#
# DoltLite's SQL dialect *is* SQLite's -- the parser, planner and VDBE are
# upstream-derived, and only the storage engine below btree.h differs. So
# rather than write a dialect, this borrows dbplyr's SQLite one wholesale via
# simulate_sqlite(), which is public API (reaching into dbplyr::: would not
# be). If DoltLite ever diverges, this is the single place to override.
#
# dbplyr is only Suggested, so the S3 methods are registered at load time
# rather than declared in NAMESPACE; a user without dbplyr pays nothing.

# dbplyr 2.x refuses to talk to a backend that has not opted into the second
# edition, with an error telling the user to contact the maintainer.
dbplyr_edition.DoltliteConnection <- function(con) 2L

# dbplyr >= 2.6
sql_dialect.DoltliteConnection <- function(con) {
  doltlite_borrow_sqlite("sql_dialect")
}

# dbplyr < 2.6 called this instead.
sql_translation.DoltliteConnection <- function(con) {
  doltlite_borrow_sqlite("sql_translation")
}

# Borrow dbplyr's SQLite translation, falling back to its default dialect.
#
# The fallback is not hypothetical: dbplyr version-gates a few of its SQLite
# translations and reads the version with RSQLite::rsqliteVersion(). It builds
# that translation table lazily, so with RSQLite absent the failure does not
# surface when the dialect is constructed -- it surfaces later, when a query is
# first rendered, where it cannot be caught cleanly. Hence the up-front check
# rather than a tryCatch. Taking a hard dependency on another SQLite backend
# just to unlock a translation table would be the wrong trade, so degrade to
# dbplyr's default dialect and say so once.
doltlite_borrow_sqlite <- function(generic) {
  fn <- getExportedValue("dbplyr", generic)

  if (requireNamespace("RSQLite", quietly = TRUE)) {
    return(fn(dbplyr::simulate_sqlite()))
  }

  if (!isTRUE(the$warned_translation)) {
    the$warned_translation <- TRUE
    packageStartupMessage(
      "doltliter: using dbplyr's default SQL translation instead of its ",
      "SQLite one.\nInstall RSQLite to get the SQLite translations ",
      "(dbplyr reads the SQLite version from it)."
    )
  }
  fn(dbplyr::simulate_dbi())
}

# Package-local mutable state, so the message above is emitted only once.
the <- new.env(parent = emptyenv())

db_connection_describe.DoltliteConnection <- function(con, ...) {
  branch <- tryCatch(doltlite_active_branch_raw(con), error = function(e) NA_character_)
  paste0(
    "doltlite ", doltlite_version(), " [", con@dbname,
    if (!is.na(branch)) paste0("@", branch) else "", "]"
  )
}

doltlite_register_dbplyr <- function() {
  if (!requireNamespace("dbplyr", quietly = TRUE)) return(invisible(FALSE))

  exports <- getNamespaceExports("dbplyr")
  register <- function(generic, method) {
    if (!generic %in% exports) return(invisible(FALSE))
    registerS3method(generic, "DoltliteConnection", method,
                     envir = asNamespace("dbplyr"))
    invisible(TRUE)
  }

  register("dbplyr_edition", dbplyr_edition.DoltliteConnection)
  register("sql_dialect", sql_dialect.DoltliteConnection)
  register("sql_translation", sql_translation.DoltliteConnection)
  register("db_connection_describe", db_connection_describe.DoltliteConnection)
  invisible(TRUE)
}
