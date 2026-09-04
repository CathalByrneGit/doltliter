#' @rdname DoltliteConnection-class
#' @param dbObj,drv,conn a `DoltliteConnection`.
#' @param ... passed on to methods.
#' @export
setMethod("dbIsValid", "DoltliteConnection", function(dbObj, ...) {
  .Call(C_dltr_is_valid, dbObj@ptr)
})

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbDisconnect", "DoltliteConnection", function(conn, ...) {
  if (!dbIsValid(conn)) {
    warning("the connection has already been disconnected", call. = FALSE)
    return(invisible(TRUE))
  }
  # DBI asks backends to complain about result sets left open at disconnect,
  # since that is nearly always a leak in the calling code.
  if (isTRUE(.Call(C_dltr_conn_info, conn@ptr)$has_open_result)) {
    warning("there is a result set still open; it is being cleared",
            call. = FALSE)
  }
  .Call(C_dltr_disconnect, conn@ptr)
  invisible(TRUE)
})

#' @rdname DoltliteConnection-class
#' @export
setMethod("show", "DoltliteConnection", function(object) {
  cat("<DoltliteConnection>\n")
  if (!dbIsValid(object)) {
    cat("  DISCONNECTED\n")
    return(invisible(object))
  }
  cat("  Database: ", object@dbname, "\n", sep = "")
  branch <- tryCatch(doltlite_active_branch_raw(object), error = function(e) NA_character_)
  cat("  Branch:   ",
      if (is.na(branch)) "<detached>" else branch, "\n", sep = "")
  invisible(object)
})

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbGetInfo", "DoltliteConnection", function(dbObj, ...) {
  info <- .Call(C_dltr_conn_info, dbObj@ptr)
  build <- doltlite_build_info()
  branch <- tryCatch(doltlite_active_branch_raw(dbObj), error = function(e) NA_character_)
  list(
    dbname = info$dbname,
    db.version = build[["sqlite_version"]],
    doltlite.engine = doltlite_engine(),
    doltlite.version = tryCatch(dolt_version(dbObj), error = function(e) NA_character_),
    branch = branch,
    readonly = info$readonly,
    username = NA_character_,
    host = NA_character_,
    port = NA_integer_
  )
})

# ------------------------------------------------------------------ queries --

#' @rdname DoltliteConnection-class
#' @param statement an SQL string.
#' @param params optional query parameters, as a list.
#' @param immediate whether to execute the statement immediately.
#' @export
setMethod("dbSendQuery", c("DoltliteConnection", "character"),
  function(conn, statement, params = NULL, ..., immediate = FALSE) {
    doltlite_send(conn, statement, params, statement_only = FALSE)
  }
)

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbSendStatement", c("DoltliteConnection", "character"),
  function(conn, statement, params = NULL, ..., immediate = FALSE) {
    doltlite_send(conn, statement, params, statement_only = TRUE)
  }
)

doltlite_send <- function(conn, statement, params, statement_only) {
  if (!dbIsValid(conn)) stop("invalid or closed connection", call. = FALSE)
  if (length(statement) != 1L || is.na(statement)) {
    stop("`statement` must be a single, non-NA string", call. = FALSE)
  }

  ptr <- .Call(C_dltr_send_query, conn@ptr, enc2utf8(statement))
  ncol <- length(.Call(C_dltr_result_column_info, ptr)$name)

  res <- new("DoltliteResult",
    ptr = ptr,
    conn = conn,
    sql = statement,
    is_statement = (ncol == 0L)
  )

  if (!is.null(params)) {
    # A failed bind would otherwise leave the result open until the garbage
    # collector got to it, and the next query on this connection would warn
    # about closing a stale result set.
    tryCatch(
      dbBind(res, params),
      error = function(e) {
        try(dbClearResult(res), silent = TRUE)
        stop(e)
      }
    )
  }
  res
}

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbGetQuery", c("DoltliteConnection", "character"),
  function(conn, statement, params = NULL, ..., n = -1, immediate = FALSE) {
    res <- dbSendQuery(conn, statement, params = params)
    on.exit(dbClearResult(res), add = TRUE)
    dbFetch(res, n = n)
  }
)

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbExecute", c("DoltliteConnection", "character"),
  function(conn, statement, params = NULL, ..., immediate = FALSE) {
    res <- dbSendStatement(conn, statement, params = params)
    on.exit(dbClearResult(res), add = TRUE)
    dbGetRowsAffected(res)
  }
)

# ------------------------------------------------------------- transactions --

#' Transactions
#'
#' These are ordinary SQLite transactions, and they are **not** Dolt commits.
#'
#' `dbBegin()` / `dbCommit()` / `dbRollback()` group statements so that they
#' either all take effect or none do. That is a property of the *working set*:
#' after `dbCommit()` the rows are in the database, but they are still
#' uncommitted from Dolt's point of view and will show up in
#' [dolt_status()].
#'
#' [dolt_commit()] is the other kind of commit: it writes a new,
#' content-addressed commit into the version history, the way `git commit`
#' does. Nothing is recorded in the history until you call it.
#'
#' A useful mental model: `dbCommit()` is "save the file", `dolt_commit()` is
#' "commit to the repository".
#'
#' One asymmetry is worth remembering: [dolt_commit()] **ends the enclosing
#' SQL transaction** as a side effect. After calling it inside a
#' `dbBegin()`/`dbCommit()` block there is no transaction left to commit, and a
#' further `dbCommit()` will report that none is active. This backend asks
#' SQLite whether a transaction is open rather than tracking it separately, so
#' [DBI::dbBegin()] and friends stay accurate either way.
#'
#' Note that DoltLite permits one durable writer at a time. A second
#' connection that begins a write transaction gets `SQLITE_BUSY` until the
#' first finishes; see the `busy_timeout` argument to [DBI::dbConnect()].
#'
#' @param conn a `DoltliteConnection`.
#' @param ... unused.
#' @name doltliter-transactions
NULL

#' @rdname doltliter-transactions
#' @export
setMethod("dbBegin", "DoltliteConnection", function(conn, ...) {
  if (!dbIsValid(conn)) stop("invalid or closed connection", call. = FALSE)
  if (doltlite_in_transaction(conn)) {
    stop("a transaction is already open on this connection", call. = FALSE)
  }
  .Call(C_dltr_exec, conn@ptr, "BEGIN")
  invisible(TRUE)
})

#' @rdname doltliter-transactions
#' @export
setMethod("dbCommit", "DoltliteConnection", function(conn, ...) {
  if (!dbIsValid(conn)) stop("invalid or closed connection", call. = FALSE)
  if (!doltlite_in_transaction(conn)) {
    stop("no transaction is open on this connection", call. = FALSE)
  }
  .Call(C_dltr_exec, conn@ptr, "COMMIT")
  invisible(TRUE)
})

#' @rdname doltliter-transactions
#' @export
setMethod("dbRollback", "DoltliteConnection", function(conn, ...) {
  if (!dbIsValid(conn)) stop("invalid or closed connection", call. = FALSE)
  if (!doltlite_in_transaction(conn)) {
    stop("no transaction is open on this connection", call. = FALSE)
  }
  .Call(C_dltr_exec, conn@ptr, "ROLLBACK")
  invisible(TRUE)
})

# ------------------------------------------------------------------- schema --

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbListTables", "DoltliteConnection", function(conn, ...) {
  # Both schemas, as RSQLite does: temporary tables are visible unqualified.
  sql <- paste(
    "SELECT name FROM sqlite_master WHERE type IN ('table','view')",
    "AND name NOT LIKE 'sqlite_%'",
    "UNION ALL",
    "SELECT name FROM sqlite_temp_master WHERE type IN ('table','view')",
    "AND name NOT LIKE 'sqlite_%'",
    "ORDER BY name"
  )
  as.character(dbGetQuery(conn, sql)$name)
})

#' @rdname DoltliteConnection-class
#' @param name a table name.
#' @export
setMethod("dbExistsTable", c("DoltliteConnection", "character"),
  function(conn, name, ...) {
    if (length(name) != 1L) stop("`name` must be a single string", call. = FALSE)
    if (is.na(name)) return(FALSE)
    sql <- paste(
      "SELECT COUNT(*) AS n FROM (",
      "  SELECT 1 FROM sqlite_master WHERE type IN ('table','view') AND name = ?",
      "  UNION ALL",
      "  SELECT 1 FROM sqlite_temp_master WHERE type IN ('table','view') AND name = ?",
      ")"
    )
    as.integer(dbGetQuery(conn, sql, params = list(name, name))$n) > 0L
  }
)

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbListFields", c("DoltliteConnection", "character"),
  function(conn, name, ...) {
    if (!dbExistsTable(conn, name)) {
      stop("no such table: ", name, call. = FALSE)
    }
    # pragma_table_info is a table-valued function, so the table name binds
    # as a value rather than being pasted into the SQL.
    res <- dbGetQuery(conn, "SELECT name FROM pragma_table_info(?)",
                      params = list(name))
    as.character(res$name)
  }
)

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbRemoveTable", c("DoltliteConnection", "character"),
  function(conn, name, ..., temporary = FALSE, fail_if_missing = TRUE) {
    if (!is.logical(temporary) || length(temporary) != 1L || is.na(temporary)) {
      stop("`temporary` must be TRUE or FALSE", call. = FALSE)
    }

    if (isTRUE(temporary)) {
      # Consider only temporary tables, and qualify the DROP with the temp
      # schema so that a permanent table of the same name is left untouched.
      found <- nrow(dbGetQuery(
        conn,
        "SELECT 1 FROM sqlite_temp_master WHERE type IN ('table','view') AND name = ?",
        params = list(name)
      )) > 0L
      if (!found) {
        if (fail_if_missing) stop("no such temporary table: ", name, call. = FALSE)
        return(invisible(FALSE))
      }
      dbExecute(conn, paste0("DROP TABLE temp.", dbQuoteIdentifier(conn, name)))
      return(invisible(TRUE))
    }

    if (!dbExistsTable(conn, name)) {
      if (fail_if_missing) stop("no such table: ", name, call. = FALSE)
      return(invisible(FALSE))
    }
    dbExecute(conn, paste0("DROP TABLE ", dbQuoteIdentifier(conn, name)))
    invisible(TRUE)
  }
)

# ---------------------------------------------------------------- data I/O --

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbReadTable", c("DoltliteConnection", "character"),
  function(conn, name, ..., row.names = FALSE, check.names = TRUE) {
    doltlite_check_row_names(row.names)
    if (!is.logical(check.names) || length(check.names) != 1L ||
        is.na(check.names)) {
      stop("`check.names` must be TRUE or FALSE", call. = FALSE)
    }
    out <- dbGetQuery(
      conn, paste0("SELECT * FROM ", dbQuoteIdentifier(conn, name))
    )
    if (isTRUE(check.names)) names(out) <- make.names(names(out), unique = TRUE)
    doltlite_apply_row_names(out, row.names)
  }
)

#' Write a data frame to a table
#'
#' Behaves as it does for any DBI backend. Two DoltLite-specific points are
#' worth knowing:
#'
#' * The default `CREATE TABLE` declares no primary key, so the table keeps an
#'   ordinary `rowid` and behaves exactly as it would under SQLite.
#' * If you use `field.types` to declare a **non-`INTEGER` primary key**, the
#'   table becomes clustered on that key. It then has no `rowid` column at all
#'   (as with SQLite's `WITHOUT ROWID`), and the key columns are `NOT NULL`.
#'   Writing `NULL` into them fails. An `INTEGER PRIMARY KEY` is unaffected --
#'   it stays a writable `rowid` alias.
#'
#' Writing a table changes the working set only. Call [dolt_commit()] to record
#' it in the version history.
#'
#' @param conn a `DoltliteConnection`.
#' @param name the table name.
#' @param value a data frame.
#' @param row.names how to treat row names; see [DBI::sqlRownamesToColumn()].
#' @param overwrite whether to drop an existing table first.
#' @param append whether to append to an existing table.
#' @param field.types a named character vector of column types.
#' @param temporary whether to create a `TEMPORARY` table.
#' @param ... unused.
#' @export
setMethod("dbWriteTable", c("DoltliteConnection", "character", "data.frame"),
  function(conn, name, value, ..., row.names = FALSE, overwrite = FALSE,
           append = FALSE, field.types = NULL, temporary = FALSE) {

    if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
      stop("`overwrite` must be TRUE or FALSE", call. = FALSE)
    }
    if (!is.logical(append) || length(append) != 1L || is.na(append)) {
      stop("`append` must be TRUE or FALSE", call. = FALSE)
    }
    if (!is.logical(temporary) || length(temporary) != 1L || is.na(temporary)) {
      stop("`temporary` must be TRUE or FALSE", call. = FALSE)
    }
    doltlite_check_row_names(row.names)
    if (overwrite && append) {
      stop("`overwrite` and `append` cannot both be TRUE", call. = FALSE)
    }
    if (append && !is.null(field.types)) {
      stop("`field.types` cannot be used when appending", call. = FALSE)
    }
    # Validate before any DDL runs, so a bad call cannot leave a half-made
    # table behind.
    doltlite_check_field_types(field.types, names(value))

    value <- DBI::sqlRownamesToColumn(value, row.names)
    # Convert factors here rather than in the parameter binder: dbWriteTable()
    # converts them as a matter of course, whereas dbAppendTable() is specified
    # to warn about it.
    value[] <- lapply(value, function(col) {
      if (is.factor(col)) as.character(col) else col
    })

    exists <- dbExistsTable(conn, name)
    if (exists && !overwrite && !append) {
      stop("table ", name, " already exists; use `overwrite = TRUE` or `append = TRUE`",
           call. = FALSE)
    }
    if (!exists && append && nrow(value) == 0L) {
      # Nothing to append to and nothing to append: create the table so the
      # end state is a table with zero rows rather than no table at all.
      append <- FALSE
    }

    if (overwrite && exists) {
      dbRemoveTable(conn, name)
      exists <- FALSE
    }

    if (!exists) {
      dbCreateTable(conn, name, value, field.types = field.types,
                    temporary = temporary)
    }

    if (nrow(value) > 0L) {
      dbAppendTable(conn, name, value)
    }
    invisible(TRUE)
  }
)

#' @rdname dbWriteTable-DoltliteConnection-character-data.frame-method
#' @param fields a data frame or named character vector defining the columns.
#' @export
setMethod("dbCreateTable", c("DoltliteConnection", "character"),
  function(conn, name, fields, ..., field.types = NULL, row.names = NULL,
           temporary = FALSE) {
    if (!is.logical(temporary) || length(temporary) != 1L || is.na(temporary)) {
      stop("`temporary` must be TRUE or FALSE", call. = FALSE)
    }
    # DBI deprecated row.names for dbCreateTable: only NULL or FALSE remain.
    if (!is.null(row.names) && !identical(row.names, FALSE)) {
      stop("`row.names` must be NULL or FALSE for dbCreateTable()",
           call. = FALSE)
    }
    if (is.data.frame(fields)) {
      fields <- DBI::sqlRownamesToColumn(fields, row.names %||% FALSE)
      types <- doltlite_data_type(fields)
    } else {
      types <- fields
    }
    doltlite_check_field_types(field.types, names(types))
    if (!is.null(field.types)) {
      unknown <- setdiff(names(field.types), names(types))
      if (length(unknown)) {
        stop("`field.types` names columns that are not present: ",
             paste(unknown, collapse = ", "), call. = FALSE)
      }
      types[names(field.types)] <- field.types
    }

    cols <- paste0(
      dbQuoteIdentifier(conn, names(types)), " ", types,
      collapse = ",\n  "
    )
    sql <- paste0(
      "CREATE ", if (temporary) "TEMPORARY " else "", "TABLE ",
      dbQuoteIdentifier(conn, name), " (\n  ", cols, "\n)"
    )
    dbExecute(conn, sql)
    invisible(TRUE)
  }
)

#' @rdname dbWriteTable-DoltliteConnection-character-data.frame-method
#' @export
setMethod("dbAppendTable", c("DoltliteConnection", "character", "data.frame"),
  function(conn, name, value, ..., row.names = NULL) {
    if (!is.null(row.names)) {
      value <- DBI::sqlRownamesToColumn(value, row.names)
    }
    if (nrow(value) == 0L) return(invisible(0L))

    placeholders <- paste(rep("?", length(value)), collapse = ", ")
    sql <- paste0(
      "INSERT INTO ", dbQuoteIdentifier(conn, name), " (",
      paste(dbQuoteIdentifier(conn, names(value)), collapse = ", "),
      ") VALUES (", placeholders, ")"
    )
    res <- dbSendStatement(conn, sql)
    on.exit(dbClearResult(res), add = TRUE)
    dbBind(res, doltlite_prepare_params(value))
    invisible(dbGetRowsAffected(res))
  }
)

# --------------------------------------------------------------- quoting ---

#' @rdname DoltliteConnection-class
#' @param x a string or identifier to quote.
#' @export
setMethod("dbQuoteIdentifier", c("DoltliteConnection", "character"),
  function(conn, x, ...) {
    if (any(is.na(x))) stop("cannot quote NA as an identifier", call. = FALSE)
    if (length(x) == 0L) return(DBI::SQL(character()))
    # SQLite's own rule: double quotes, doubled to escape.
    DBI::SQL(paste0('"', gsub('"', '""', x, fixed = TRUE), '"'),
             names = names(x))
  }
)

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbQuoteIdentifier", c("DoltliteConnection", "SQL"),
  function(conn, x, ...) x
)

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbQuoteString", c("DoltliteConnection", "character"),
  function(conn, x, ...) {
    # paste0() recycles a zero-length argument to "", which would turn
    # character(0) into a single "''" instead of nothing.
    if (length(x) == 0L) return(DBI::SQL(character()))
    out <- paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
    out[is.na(x)] <- "NULL"
    DBI::SQL(out)
  }
)

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbQuoteString", c("DoltliteConnection", "SQL"),
  function(conn, x, ...) x
)

# --------------------------------------------------------------- internals ---

`%||%` <- function(x, y) if (is.null(x)) y else x

# SQLite is the authority on whether a transaction is open. dolt_commit() ends
# the enclosing SQL transaction as a side effect, so a flag maintained on the R
# side would go stale without anything here noticing.
doltlite_in_transaction <- function(conn) {
  isTRUE(.Call(C_dltr_in_transaction, conn@ptr))
}

# DBI lets a table be named by a bare string, an Id(), or an already-quoted
# SQL() identifier. Everything below works with the plain name, so normalise
# once here rather than in each method.
doltlite_table_name <- function(name) {
  if (methods::is(name, "Id")) {
    parts <- name@name
    if (length(parts) == 0L) stop("empty Id()", call. = FALSE)
    return(unname(parts[[length(parts)]]))
  }
  if (methods::is(name, "SQL")) {
    return(vapply(as.character(name), doltlite_unquote_identifier, character(1),
                  USE.NAMES = FALSE))
  }
  as.character(name)
}

# Strip one layer of identifier quoting.
#
# All three styles have to be handled, not just the one this package emits.
# dbQuoteIdentifier() here produces "double quotes", but dbplyr's SQLite
# dialect quotes with `backticks`, so an already-quoted identifier arriving
# from copy_to() or compute() is backticked. Missing that created tables
# literally named `measurements`, backticks included, which then could not be
# found by anything that quoted the name properly.
doltlite_unquote_identifier <- function(x) {
  if (grepl('^".*"$', x)) {
    return(gsub('""', '"', sub('^"(.*)"$', "\\1", x), fixed = TRUE))
  }
  if (grepl("^`.*`$", x)) {
    return(gsub("``", "`", sub("^`(.*)`$", "\\1", x), fixed = TRUE))
  }
  if (grepl("^\\[.*\\]$", x)) {
    return(sub("^\\[(.*)\\]$", "\\1", x))
  }
  x
}


doltlite_check_field_types <- function(field.types, columns) {
  if (is.null(field.types)) return(invisible(TRUE))
  if (!is.character(field.types) || is.null(names(field.types)) ||
      anyNA(field.types) || any(!nzchar(names(field.types)))) {
    stop("`field.types` must be a named character vector of column types",
         call. = FALSE)
  }
  if (anyDuplicated(names(field.types))) {
    stop("`field.types` has duplicate column names", call. = FALSE)
  }
  invisible(TRUE)
}

# DBI allows NULL, NA, TRUE/FALSE, or a single column name.
doltlite_check_row_names <- function(row.names) {
  if (is.null(row.names)) return(invisible(TRUE))
  if (length(row.names) != 1L) {
    stop("`row.names` must be NULL, a logical flag, or a single column name",
         call. = FALSE)
  }
  if (is.logical(row.names) || is.character(row.names)) return(invisible(TRUE))
  stop("`row.names` must be NULL, a logical flag, or a single column name",
       call. = FALSE)
}

doltlite_apply_row_names <- function(out, row.names) {
  DBI::sqlColumnToRownames(out, row.names)
}

# A data frame is the natural shape for a parameter set, but the C layer wants
# a plain list of columns, with factors and dates already reduced to something
# SQLite understands.
doltlite_prepare_params <- function(value) {
  lapply(unname(as.list(value)), doltlite_coerce_param)
}

doltlite_coerce_param <- function(col) {
  if (is.factor(col)) {
    warning("factor values are converted to character", call. = FALSE)
    return(as.character(col))
  }
  if (inherits(col, "blob")) return(unclass(col))
  if (inherits(col, "Date")) return(as.numeric(col))
  if (inherits(col, "POSIXct")) return(as.numeric(col))
  if (inherits(col, "difftime")) return(as.numeric(col))
  if (is.list(col) && !inherits(col, "integer64")) return(unclass(col))
  col
}


# ---------------------------------------------------- Id / SQL table names ---
# DBI's generics accept Id() and SQL() wherever a table name is expected. Each
# of these normalises the name and hands off to the character method, so the
# real implementation lives in exactly one place.

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbExistsTable", c("DoltliteConnection", "SQL"),
  function(conn, name, ...) dbExistsTable(conn, doltlite_table_name(name), ...))

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbListFields", c("DoltliteConnection", "SQL"),
  function(conn, name, ...) dbListFields(conn, doltlite_table_name(name), ...))

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbReadTable", c("DoltliteConnection", "SQL"),
  function(conn, name, ...) dbReadTable(conn, doltlite_table_name(name), ...))

#' @rdname DoltliteConnection-class
#' @export
setMethod("dbRemoveTable", c("DoltliteConnection", "SQL"),
  function(conn, name, ...) dbRemoveTable(conn, doltlite_table_name(name), ...))

#' @rdname dbWriteTable-DoltliteConnection-character-data.frame-method
#' @export
setMethod("dbWriteTable", c("DoltliteConnection", "SQL", "data.frame"),
  function(conn, name, value, ...)
    dbWriteTable(conn, doltlite_table_name(name), value, ...))

#' @rdname dbWriteTable-DoltliteConnection-character-data.frame-method
#' @export
setMethod("dbCreateTable", c("DoltliteConnection", "SQL"),
  function(conn, name, fields, ...)
    dbCreateTable(conn, doltlite_table_name(name), fields, ...))

#' @rdname dbWriteTable-DoltliteConnection-character-data.frame-method
#' @export
setMethod("dbAppendTable", c("DoltliteConnection", "SQL", "data.frame"),
  function(conn, name, value, ...)
    dbAppendTable(conn, doltlite_table_name(name), value, ...))
