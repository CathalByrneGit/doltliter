#' Configure the committer identity
#'
#' Set or read the `user.name` / `user.email` used by [dolt_commit()],
#' [dolt_merge()], [dolt_cherry_pick()] and [dolt_revert()].
#'
#' Configuration is **per connection** and is not persisted. Set it after
#' connecting, on every connection that will commit.
#'
#' @param con a `DoltliteConnection`.
#' @param key a setting name, e.g. `"user.name"`. Omit to read nothing.
#' @param value a value to set. Omit to read the current value instead.
#' @param user.name,user.email a convenience shorthand; supply either or both
#'   instead of `key`/`value`.
#' @return When reading, the value. When setting, invisibly `TRUE`.
#' @export
#' @examples
#' con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
#' dolt_config(con, user.name = "Ada Lovelace", user.email = "ada@example.com")
#' dolt_config(con, "user.name")
#' DBI::dbDisconnect(con)
dolt_config <- function(con, key = NULL, value = NULL,
                        user.name = NULL, user.email = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_config")

  if (!is.null(user.name)) dolt_scalar(con, "dolt_config", "user.name", user.name)
  if (!is.null(user.email)) dolt_scalar(con, "dolt_config", "user.email", user.email)

  if (is.null(key)) {
    if (is.null(user.name) && is.null(user.email)) {
      stop("supply `key`, or `user.name`/`user.email`", call. = FALSE)
    }
    return(invisible(TRUE))
  }

  if (is.null(value)) {
    return(dolt_scalar(con, "dolt_config", key))
  }
  dolt_scalar(con, "dolt_config", key, value)
  invisible(TRUE)
}

#' Stage tables
#'
#' @param con a `DoltliteConnection`.
#' @param tables table names to stage. Omit, or pass `all = TRUE`, to stage
#'   everything.
#' @param all stage all tables (`dolt_add('-A')`).
#' @return Invisibly `TRUE`.
#' @export
dolt_add <- function(con, tables = NULL, all = is.null(tables)) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_add")
  if (isTRUE(all)) {
    dolt_scalar(con, "dolt_add", "-A")
  } else {
    if (length(tables) == 0L) {
      stop("supply `tables`, or use `all = TRUE`", call. = FALSE)
    }
    # dolt_add takes one table per call, which keeps the error attributable
    # to the offending table rather than to the batch.
    for (tbl in tables) dolt_scalar(con, "dolt_add", tbl)
  }
  invisible(TRUE)
}

#' Commit the current working set
#'
#' Records a new commit in the version history. This is the Dolt sense of
#' "commit" and has nothing to do with [DBI::dbCommit()], which ends a SQL
#' transaction; see [doltliter-transactions].
#'
#' @param con a `DoltliteConnection`.
#' @param message the commit message.
#' @param author optionally `"Name <email>"`, overriding [dolt_config()] for
#'   this commit only.
#' @param all stage every changed table first, like `git commit -a`
#'   (the default).
#' @param allow_empty create a commit even when nothing changed.
#' @param force commit despite outstanding constraint violations.
#' @return The new commit hash, invisibly.
#' @export
#' @examples
#' con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
#' dolt_config(con, user.name = "Ada", user.email = "ada@example.com")
#' DBI::dbWriteTable(con, "users", data.frame(id = 1:2, nm = c("a", "b")))
#' dolt_commit(con, "Initial load")
#' dolt_log(con)$message
#' DBI::dbDisconnect(con)
dolt_commit <- function(con, message, author = NULL, all = TRUE,
                        allow_empty = FALSE, force = FALSE) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_commit")
  if (!is.character(message) || length(message) != 1L || is.na(message)) {
    stop("`message` must be a single, non-NA string", call. = FALSE)
  }

  # Flags first, then the message, then any long options -- the order
  # dolt_commit expects.
  args <- if (isTRUE(all)) list("-Am", message) else list("-m", message)
  if (!is.null(author)) args <- c(args, list("--author", author))
  if (isTRUE(allow_empty)) args <- c(args, list("--allow-empty"))
  if (isTRUE(force)) args <- c(args, list("--force"))

  invisible(do.call(dolt_scalar, c(list(con, "dolt_commit"), args)))
}

#' Working-set status
#'
#' @param con a `DoltliteConnection`.
#' @return A data frame with columns `table_name`, `staged` and `status`. Zero
#'   rows means the working set is clean.
#' @export
dolt_status <- function(con) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_status")
  dolt_table(con, "dolt_status")
}

#' Undo uncommitted work
#'
#' @param con a `DoltliteConnection`.
#' @param mode `"soft"` unstages everything but keeps the working changes;
#'   `"hard"` discards uncommitted changes outright.
#' @return Invisibly `TRUE`.
#' @export
dolt_reset <- function(con, mode = c("soft", "hard")) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_reset")
  mode <- match.arg(mode)
  dolt_scalar(con, "dolt_reset", paste0("--", mode))
  invisible(TRUE)
}

#' Revert a commit
#'
#' Creates a new commit applying the inverse of `ref`. The initial commit
#' cannot be reverted.
#'
#' @param con a `DoltliteConnection`.
#' @param ref a commit hash or ref to revert.
#' @return The result string: a new commit hash, or a message reporting
#'   conflicts.
#' @export
dolt_revert <- function(con, ref) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_revert")
  dolt_scalar(con, "dolt_revert", ref)
}

#' Cherry-pick a commit
#'
#' Applies one commit's changes onto the current branch. Ranges are not
#' supported by DoltLite.
#'
#' @param con a `DoltliteConnection`.
#' @param ref the commit to apply.
#' @return The new commit hash, or a message reporting conflicts.
#' @export
dolt_cherry_pick <- function(con, ref) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_cherry_pick")
  dolt_scalar(con, "dolt_cherry_pick", ref)
}

#' DoltLite version
#'
#' @param con a `DoltliteConnection`.
#' @return The DoltLite version string.
#'
#'   Note that a package built from the DoltLite *amalgamation* reports
#'   whatever version `configure` stamped in; a package linked against a
#'   prebuilt library reports the version compiled into that library. Use
#'   [doltlite_engine()] if all you need is to confirm the storage engine.
#' @export
dolt_version <- function(con) {
  dolt_require_conn(con)
  dolt_scalar(con, "dolt_version")
}

#' Garbage-collect unreachable chunks
#'
#' @param con a `DoltliteConnection`.
#' @return A summary string, e.g. `"12 chunks removed, 45 chunks kept"`.
#' @export
dolt_gc <- function(con) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_gc")
  dolt_scalar(con, "dolt_gc")
}

#' Content-addressed hashes
#'
#' @param con a `DoltliteConnection`.
#' @param ref a branch, tag, commit hash, `HEAD`, `HEAD~N` or `HEAD^N`.
#' @param table a table name.
#' @return A 40-character lowercase hex hash.
#' @export
dolt_hashof <- function(con, ref = "HEAD") {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_hashof")
  dolt_scalar(con, "dolt_hashof", ref)
}

#' @rdname dolt_hashof
#' @export
dolt_hashof_table <- function(con, table, ref = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_hashof_table")
  dolt_scalar(con, "dolt_hashof_table", table, ref)
}

#' @rdname dolt_hashof
#' @export
dolt_hashof_db <- function(con, ref = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_hashof_db")
  dolt_scalar(con, "dolt_hashof_db", ref)
}

#' Re-check constraints
#'
#' @param con a `DoltliteConnection`.
#' @param tables optional table names; omit to check all.
#' @param all pass `--all`.
#' @param output_only pass `--output-only`.
#' @return The function's return value.
#' @export
dolt_verify_constraints <- function(con, tables = NULL, all = FALSE,
                                    output_only = FALSE) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_verify_constraints")
  args <- list()
  if (isTRUE(all)) args <- c(args, list("--all"))
  if (isTRUE(output_only)) args <- c(args, list("--output-only"))
  if (length(tables)) args <- c(args, as.list(tables))
  do.call(dolt_scalar, c(list(con, "dolt_verify_constraints"), args))
}
