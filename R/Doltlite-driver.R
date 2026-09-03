#' Create a DoltLite driver object
#'
#' `Doltlite()` creates the driver object passed to [DBI::dbConnect()]. It
#' carries no state: connection options belong to `dbConnect()`.
#'
#' @param drv,dbObj,object a `DoltliteDriver`, as returned by `Doltlite()`.
#' @param ... unused, for compatibility with the DBI generics.
#' @return `Doltlite()` returns a `DoltliteDriver`. `dbGetInfo()` returns a
#'   list describing the driver and the DoltLite build behind it.
#' @export
#' @examples
#' con <- DBI::dbConnect(doltliter::Doltlite(), ":memory:")
#' DBI::dbGetQuery(con, "SELECT doltlite_engine()")
#' DBI::dbDisconnect(con)
#' @export
Doltlite <- function() {
  new("DoltliteDriver")
}

#' @rdname Doltlite
#' @export
setMethod("dbUnloadDriver", "DoltliteDriver", function(drv, ...) {
  invisible(TRUE)
})

#' @rdname Doltlite
#' @export
setMethod("dbIsValid", "DoltliteDriver", function(dbObj, ...) TRUE)

#' @rdname Doltlite
#' @export
setMethod("show", "DoltliteDriver", function(object) {
  cat("<DoltliteDriver>\n")
  invisible(object)
})

#' @rdname Doltlite
#' @export
setMethod("dbGetInfo", "DoltliteDriver", function(dbObj, ...) {
  info <- doltlite_build_info()
  list(
    driver.version = utils::packageVersion("doltliter"),
    client.version = info[["sqlite_version"]],
    doltlite.engine = doltlite_engine(),
    max.connections = NA_integer_
  )
})

#' SQL type for an R object
#'
#' DoltLite uses SQLite's type names and affinity rules, so the mapping is
#' SQLite's. The one addition is `integer64`, which maps to `INTEGER` because
#' SQLite integers are already 64-bit.
#'
#' @param dbObj a driver or connection
#' @param obj an R object
#' @param ... unused
#' @export
setMethod("dbDataType", "DoltliteDriver", function(dbObj, obj, ...) {
  doltlite_data_type(obj)
})

#' @rdname dbDataType-DoltliteDriver-method
#' @export
setMethod("dbDataType", "DoltliteConnection", function(dbObj, obj, ...) {
  doltlite_data_type(obj)
})

doltlite_data_type <- function(obj) {
  if (is.data.frame(obj)) {
    return(vapply(obj, doltlite_data_type, character(1)))
  }
  if (inherits(obj, "integer64")) return("INTEGER")
  if (inherits(obj, "blob")) return("BLOB")
  if (is.factor(obj)) return("TEXT")
  if (inherits(obj, c("Date", "POSIXct", "difftime"))) return("REAL")
  switch(typeof(obj),
    logical   = "INTEGER",
    integer   = "INTEGER",
    double    = "REAL",
    character = "TEXT",
    raw       = "BLOB",
    list      = "BLOB",
    stop("cannot map an object of type '", typeof(obj),
         "' to a DoltLite column type", call. = FALSE)
  )
}

#' Connect to a DoltLite database
#'
#' @param drv a [Doltlite()] driver.
#' @param dbname path to the database file. `":memory:"` opens a private
#'   in-memory database. An empty string opens an anonymous temporary
#'   database, which SQLite -- and therefore DoltLite -- creates in its
#'   *original* B-tree format, so version control is **not** available there;
#'   use [tempfile()] instead if you need it.
#' @param branch branch to check out on connect. Translated to DoltLite's
#'   `dbname@branch` path syntax internally. The branch must already exist;
#'   opening a database that does not have it is an error rather than a silent
#'   fall back to `main`.
#' @param flags one of `DOLTLITE_RWC` (read/write/create, the default),
#'   `DOLTLITE_RW` or `DOLTLITE_RO`.
#' @param vfs an optional SQLite VFS name.
#' @param bigint how to return 64-bit integers that do not fit in an R
#'   integer: `"integer64"` (default), `"integer"`, `"numeric"` or
#'   `"character"`.
#' @param busy_timeout milliseconds to wait for the DoltLite graph lock before
#'   giving up with `SQLITE_BUSY`. DoltLite permits one durable writer at a
#'   time, so a non-zero value is usually what you want.
#' @param ... unused.
#'
#' @return A `DoltliteConnection`.
#' @export
setMethod("dbConnect", "DoltliteDriver",
  function(drv, dbname = ":memory:", branch = NULL,
           flags = DOLTLITE_RWC, vfs = NULL,
           bigint = c("integer64", "integer", "numeric", "character"),
           busy_timeout = 5000L, ...) {

    if (!is.character(dbname) || length(dbname) != 1L || is.na(dbname)) {
      stop("`dbname` must be a single, non-NA string", call. = FALSE)
    }
    bigint <- match.arg(bigint)

    path <- doltlite_expand_dbname(dbname)
    open_path <- doltlite_qualify(path, branch)

    ptr <- withCallingHandlers(
      tryCatch(
        .Call(
          C_dltr_connect,
          open_path,
          as.integer(flags),
          if (is.null(vfs)) NA_character_ else as.character(vfs),
          match(bigint, c("integer64", "integer", "numeric", "character")) - 1L,
          as.integer(busy_timeout)
        ),
        error = function(e) {
          # Opening `db@branch` for a branch that does not exist fails inside
          # SQLite with a bare "SQL logic error", which tells the user nothing.
          if (!is.null(branch)) {
            # Strip the C layer's own "could not connect to '<path@branch>':"
            # prefix so the branch is named once, not twice.
            detail <- sub("^could not connect to '[^']*': ", "",
                          conditionMessage(e))
            stop(sprintf(
              "could not open '%s' at branch '%s': %s\nIf the branch does not exist yet, connect without `branch=` and create it with dolt_branch().",
              path, branch, detail
            ), call. = FALSE)
          }
          stop(e)
        }
      ),
      warning = function(w) w
    )

    con <- new("DoltliteConnection",
      ptr = ptr,
      dbname = path,
      branch = if (is.null(branch)) NA_character_ else as.character(branch),
      bigint = bigint,
      state = new.env(parent = emptyenv())
    )
    con@state$transacting <- FALSE
    con@state$known_engine <- NULL

    # A branch suffix on a database that does not yet exist is silently
    # ignored by DoltLite: you land on `main`. Failing loudly beats handing
    # back a connection to the wrong branch.
    if (!is.null(branch)) {
      actual <- tryCatch(doltlite_active_branch_raw(con), error = function(e) NA_character_)
      if (is.na(actual) || !identical(actual, as.character(branch))) {
        DBI::dbDisconnect(con)
        stop(sprintf(
          "branch '%s' is not available in '%s' (connected to %s instead).\nCreate it first with dolt_branch(), or connect without `branch=`.",
          branch, path,
          if (is.na(actual)) "a detached revision" else sprintf("'%s'", actual)
        ), call. = FALSE)
      }
    }

    con
  }
)

# ":memory:" and "" are SQLite keywords, not paths, and `file:` URIs must be
# left exactly as given.
doltlite_expand_dbname <- function(dbname) {
  if (dbname %in% c(":memory:", "")) return(dbname)
  if (grepl("^file:", dbname)) return(dbname)
  path.expand(dbname)
}

# DoltLite accepts both `db@branch` and `db/branch`. The `/` form is
# indistinguishable from an ordinary path separator, so doltliter only ever
# emits `@`. Note that normalizePath() is deliberately not used: a
# `db@branch` string does not name an existing file, so normalising it would
# either fail or mangle the suffix.
doltlite_qualify <- function(path, branch) {
  if (is.null(branch)) return(path)

  if (!is.character(branch) || length(branch) != 1L || is.na(branch) ||
      !nzchar(branch)) {
    stop("`branch` must be a single, non-empty string", call. = FALSE)
  }
  if (grepl("@", path, fixed = TRUE)) {
    stop("`dbname` already carries an `@revision` suffix; supply either that or `branch=`, not both",
         call. = FALSE)
  }
  if (path %in% c(":memory:", "")) {
    stop("`branch=` is not meaningful for an in-memory or anonymous database: ",
         "DoltLite ignores the suffix and opens `main`.", call. = FALSE)
  }
  paste0(path, "@", branch)
}
