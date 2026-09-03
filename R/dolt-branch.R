# Used by show()/dbGetInfo() on a connection, so it must not require a
# DoltLite-format database: on a stock SQLite file active_branch() does not
# exist, and the caller wants NA rather than an error.
doltlite_active_branch_raw <- function(con) {
  out <- tryCatch(
    dbGetQuery(con, "SELECT active_branch() AS b")$b,
    error = function(e) NA_character_
  )
  if (length(out) == 0L) return(NA_character_)
  as.character(out[[1L]])
}

#' The current branch
#'
#' @param con a `DoltliteConnection`.
#' @return The branch name, or `NA` when the connection is on a detached
#'   revision (opened at a tag, commit hash or ancestor spec), which is
#'   read-only.
#' @export
#' @examples
#' con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
#' dolt_active_branch(con)
#' DBI::dbDisconnect(con)
dolt_active_branch <- function(con) {
  dolt_require_conn(con)
  doltlite_active_branch_raw(con)
}

#' @rdname dolt_active_branch
#' @export
active_branch <- function(con) dolt_active_branch(con)

#' Create, list or delete branches
#'
#' @param con a `DoltliteConnection`.
#' @param name the branch name. Omit to list branches instead.
#' @param delete delete `name` rather than creating it.
#' @param force overwrite an existing branch.
#' @return When listing, a data frame of branches. Otherwise invisibly `TRUE`.
#' @export
#' @examples
#' con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
#' dolt_config(con, user.name = "Ada", user.email = "ada@example.com")
#' DBI::dbWriteTable(con, "t", data.frame(x = 1))
#' dolt_commit(con, "init")
#' dolt_branch(con, "experiment")
#' dolt_branch(con)$name
#' DBI::dbDisconnect(con)
dolt_branch <- function(con, name = NULL, delete = FALSE, force = FALSE) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_branch")

  if (is.null(name)) return(dolt_branches(con))

  args <- list()
  if (isTRUE(delete)) args <- c(args, list(if (isTRUE(force)) "-D" else "-d"))
  else if (isTRUE(force)) args <- c(args, list("-f"))
  args <- c(args, list(name))

  do.call(dolt_scalar, c(list(con, "dolt_branch"), args))
  invisible(TRUE)
}

#' @rdname dolt_branch
#' @export
dolt_branches <- function(con) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_branches")
  dolt_table(con, "dolt_branches")
}

#' Switch branches
#'
#' Each connection tracks its own active branch. Uncommitted work belongs to
#' the *branch*, not the connection, so another connection that checks out the
#' same branch sees the same working set. There is no stash: checking out does
#' not shelve uncommitted changes.
#'
#' @param con a `DoltliteConnection`.
#' @param name the branch to check out.
#' @param create create the branch first (`dolt_checkout('-b', name)`).
#' @return Invisibly `TRUE`.
#' @export
dolt_checkout <- function(con, name, create = FALSE) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_checkout")
  if (isTRUE(create)) {
    dolt_scalar(con, "dolt_checkout", "-b", name)
  } else {
    dolt_scalar(con, "dolt_checkout", name)
  }
  invisible(TRUE)
}

#' Merge a branch into the current one
#'
#' A three-way, row-level merge. Non-conflicting row edits merge
#' automatically; edits to the same row become conflicts.
#'
#' @section Conflicts require an explicit transaction:
#'
#' Conflicts are never durable in DoltLite: they exist only inside the
#' transaction that produced them. A merge run in autocommit mode -- which is
#' what you get by default -- is therefore **rolled back in full** the moment
#' it conflicts, and `dolt_merge()` raises an error rather than returning a
#' conflict count. There is then nothing left in `dolt_conflicts()` to inspect,
#' because nothing conflicted was kept.
#'
#' To handle conflicts, wrap the merge in a transaction:
#'
#' ```r
#' DBI::dbBegin(con)
#' dolt_merge(con, "feature")           # returns a conflict report
#' dolt_conflicts(con)                  # inspect
#' dolt_conflicts_resolve(con, "ours")  # or "theirs", or edit rows directly
#' dolt_commit(con, "merge feature")
#' DBI::dbCommit(con)
#' ```
#'
#' A commit is refused while any conflict remains. A merge that is expected to
#' be clean needs no transaction.
#'
#' @param con a `DoltliteConnection`.
#' @param name the branch to merge in.
#' @return The merge commit hash on a clean merge, otherwise a string
#'   reporting the conflict count. Errors if the merge conflicts outside a
#'   transaction, since DoltLite rolls such a merge back whole.
#' @seealso [dolt_conflicts()], [doltliter-transactions]
#' @export
dolt_merge <- function(con, name) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_merge")

  # DoltLite reports a conflicting merge as a SQL error, not as a return
  # value. Inside a transaction that is not a failure -- the conflicts are
  # sitting there waiting to be resolved -- so turn it back into the conflict
  # report the caller expects. In autocommit the same merge is rolled back
  # whole and nothing survives to resolve, so there the error stands.
  tryCatch(
    dolt_scalar(con, "dolt_merge", name),
    error = function(e) {
      msg <- conditionMessage(e)
      if (!grepl("conflict", msg, ignore.case = TRUE)) stop(e)
      pending <- tryCatch(nrow(dolt_conflicts(con)) > 0L,
                          error = function(e2) FALSE)
      if (!pending) stop(e)
      msg
    }
  )
}

#' Merge status
#'
#' @param con a `DoltliteConnection`.
#' @return A one-row data frame. `is_merging` is `0` and the other columns are
#'   `NA` when no merge is in progress.
#' @export
dolt_merge_status <- function(con) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_merge_status")
  dolt_table(con, "dolt_merge_status")
}

#' Merge base of two commits
#'
#' @param con a `DoltliteConnection`.
#' @param a,b commit hashes or refs.
#' @return The merge-base commit hash.
#' @export
dolt_merge_base <- function(con, a, b) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_merge_base")
  dolt_scalar(con, "dolt_merge_base", a, b)
}

#' Conflicts
#'
#' `dolt_conflicts()` summarises conflicted tables. `dolt_conflicts_table()`
#' returns the per-row detail, with `base_`/`our_`/`their_` columns and a
#' `dolt_conflict_id`. `dolt_conflicts_resolve()` takes one side wholesale.
#'
#' @param con a `DoltliteConnection`.
#' @param table a table name.
#' @param side `"ours"` or `"theirs"`.
#' @param tables tables to resolve; omit to resolve every conflicted table.
#' @return A data frame, or invisibly `TRUE` for the resolver.
#' @export
dolt_conflicts <- function(con) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_conflicts")
  dolt_table(con, "dolt_conflicts")
}

#' @rdname dolt_conflicts
#' @export
dolt_conflicts_table <- function(con, table) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_conflicts_table")
  dolt_table_suffixed(con, "dolt_conflicts_", table)
}

#' @rdname dolt_conflicts
#' @export
dolt_conflicts_resolve <- function(con, side = c("ours", "theirs"),
                                   tables = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_conflicts_resolve")
  side <- match.arg(side)
  if (is.null(tables)) {
    tables <- as.character(dolt_conflicts(con)[[1L]])
    if (length(tables) == 0L) {
      stop("there are no conflicted tables to resolve", call. = FALSE)
    }
  }
  for (tbl in tables) {
    dolt_scalar(con, "dolt_conflicts_resolve", paste0("--", side), tbl)
  }
  invisible(TRUE)
}

#' Constraint violations left by a merge
#'
#' Merges apply cell by cell and do not run referential actions inline, so
#' violating rows land here afterwards. A commit is refused while any remain
#' unless `force = TRUE`.
#'
#' @param con a `DoltliteConnection`.
#' @param table optionally a table name, for the per-table detail.
#' @return A data frame.
#' @export
dolt_constraint_violations <- function(con, table = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_constraint_violations")
  if (is.null(table)) return(dolt_table(con, "dolt_constraint_violations"))
  dolt_table_suffixed(con, "dolt_constraint_violations_", table)
}

#' Tags
#'
#' @param con a `DoltliteConnection`.
#' @param name the tag name. Omit to list tags.
#' @param ref the commit to tag; defaults to `HEAD`.
#' @param delete delete the tag instead of creating it.
#' @return A data frame when listing, otherwise invisibly `TRUE`.
#' @export
dolt_tag <- function(con, name = NULL, ref = NULL, delete = FALSE) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_tag")
  if (is.null(name)) return(dolt_tags(con))
  if (isTRUE(delete)) {
    dolt_scalar(con, "dolt_tag", "-d", name)
  } else {
    dolt_scalar(con, "dolt_tag", name, ref)
  }
  invisible(TRUE)
}

#' @rdname dolt_tag
#' @export
dolt_tags <- function(con) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_tags")
  dolt_table(con, "dolt_tags")
}

#' Rebase the current branch onto another
#'
#' Atomic: a conflict or error restores the pre-rebase branch.
#'
#' @param con a `DoltliteConnection`.
#' @param upstream the branch to replay onto.
#' @param interactive start an interactive rebase, which populates the
#'   `dolt_rebase` plan table for editing with ordinary SQL.
#' @param continue,abort finish or abandon an interactive rebase.
#' @return The result string.
#' @export
dolt_rebase <- function(con, upstream = NULL, interactive = FALSE,
                        continue = FALSE, abort = FALSE) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_rebase")
  if (isTRUE(continue)) return(dolt_scalar(con, "dolt_rebase", "--continue"))
  if (isTRUE(abort)) return(dolt_scalar(con, "dolt_rebase", "--abort"))
  if (is.null(upstream)) {
    stop("supply `upstream`, or one of `continue`/`abort`", call. = FALSE)
  }
  if (isTRUE(interactive)) {
    dolt_scalar(con, "dolt_rebase", "-i", upstream)
  } else {
    dolt_scalar(con, "dolt_rebase", upstream)
  }
}
