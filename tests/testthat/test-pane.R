ns <- asNamespace("doltliter")

test_that("connection discovery finds exactly one open connection", {
  con <- local_dolt()
  e <- new.env(parent = emptyenv())
  assign("mycon", con, envir = e)
  assign("unrelated", 42L, envir = e)

  expect_identical(ns$doltlite_find_connection(e), con)
})

test_that("connection discovery refuses to guess", {
  con1 <- local_dolt()
  con2 <- local_dolt()

  empty <- new.env(parent = emptyenv())
  expect_error(ns$doltlite_find_connection(empty), "no open DoltliteConnection")

  two <- new.env(parent = emptyenv())
  assign("a", con1, envir = two)
  assign("b", con2, envir = two)
  # Ambiguity must error rather than pick one: the wrong choice here acts on
  # the wrong database.
  expect_error(ns$doltlite_find_connection(two), "found 2 open connections")
  expect_error(ns$doltlite_find_connection(two), "a, b")
})

test_that("closed connections are not offered", {
  con <- DBI::dbConnect(doltliter::Doltlite(), tempfile(fileext = ".db"))
  DBI::dbDisconnect(con)
  e <- new.env(parent = emptyenv())
  assign("dead", con, envir = e)

  expect_error(ns$doltlite_find_connection(e), "no open DoltliteConnection")
})

test_that("pane status returns a stable shape when clean", {
  con <- local_dolt()
  DBI::dbWriteTable(con, "t", data.frame(id = 1:2))
  dolt_commit(con, "init")

  st <- ns$doltlite_pane_status(con)
  expect_s3_class(st, "data.frame")
  expect_identical(nrow(st), 0L)
  expect_true(all(c("table_name", "staged", "status") %in% names(st)))
})

test_that("pane status reports a modified table", {
  con <- local_dolt()
  DBI::dbWriteTable(con, "t", data.frame(id = 1:2, v = c("a", "b")))
  dolt_commit(con, "init")
  DBI::dbExecute(con, "UPDATE t SET v = 'z' WHERE id = 1")

  st <- ns$doltlite_pane_status(con)
  expect_identical(nrow(st), 1L)
  expect_identical(st$table_name, "t")
})

test_that("the gadget refuses a connection that is not version controlled", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("miniUI")
  skip_if_not_installed("DT")

  con <- DBI::dbConnect(doltliter::Doltlite(), "")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  expect_error(doltliter::dolt_pane(con), "needs a DoltLite-format database")
})

test_that("dolt_pane() reports missing Suggests rather than failing obscurely", {
  # Simulate shiny being absent by calling the guard with a stub in place.
  local_mocked_bindings(
    requireNamespace = function(package, ...) {
      if (package %in% c("shiny", "miniUI", "DT")) FALSE else TRUE
    },
    .package = "base"
  )
  expect_error(ns$doltlite_require_shiny(), "shiny, miniUI and DT")
})

# The reactive logic is the part worth testing: shiny::testServer runs it
# without a browser, so the commit guard and the refresh cycle are covered
# rather than just the helpers around them.

test_that("the UI builds for a real connection", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("miniUI")
  skip_if_not_installed("DT")
  con <- local_dolt()
  expect_s3_class(ns$doltlite_pane_ui(con), "shiny.tag.list")
})

test_that("server reports the connection's own branch", {
  skip_if_not_installed("shiny")
  con <- local_dolt()
  seed_users(con)
  dolt_checkout(con, "feature", create = TRUE)

  shiny::testServer(ns$doltlite_pane_server(con), {
    expect_identical(output$branch, "feature")
  })
})

test_that("server lists changed tables and clears after commit", {
  skip_if_not_installed("shiny")
  con <- local_dolt()
  seed_users(con)
  DBI::dbExecute(con, "UPDATE users SET active = 1 WHERE id = 2")

  shiny::testServer(ns$doltlite_pane_server(con), {
    expect_identical(nrow(status()), 1L)

    session$setInputs(msg = "activate bob", commit = 1)
    expect_identical(output$commit_msg, "committed")
    expect_identical(nrow(status()), 0L)
  })

  expect_identical(dolt_log(con)$message[[1]], "activate bob")
})

test_that("server refuses to commit while a transaction is open", {
  skip_if_not_installed("shiny")
  con <- local_dolt()
  seed_users(con)

  DBI::dbBegin(con)
  DBI::dbExecute(con, "UPDATE users SET active = 1 WHERE id = 2")

  shiny::testServer(ns$doltlite_pane_server(con), {
    session$setInputs(msg = "should not land", commit = 1)
    expect_match(output$commit_msg, "transaction is open")
  })

  # The guard must leave the transaction alone, not quietly end it.
  expect_true(ns$doltlite_in_transaction(con))
  expect_false("should not land" %in% dolt_log(con)$message)

  # Rolled back here rather than via on.exit: local_dolt() defers its
  # disconnect on this same frame, and would close the connection first.
  DBI::dbRollback(con)
})

test_that("server requires a commit message", {
  skip_if_not_installed("shiny")
  con <- local_dolt()
  seed_users(con)
  DBI::dbExecute(con, "UPDATE users SET active = 1 WHERE id = 2")

  shiny::testServer(ns$doltlite_pane_server(con), {
    session$setInputs(msg = "   ", commit = 1)
    expect_match(output$commit_msg, "commit message")
    expect_identical(nrow(status()), 1L)
  })
})

# The DT table builders are pure, so they are tested directly rather than
# through the reactives.

test_that("diff table drops commit columns and leads with diff_type", {
  skip_if_not_installed("DT")
  con <- local_dolt()
  seed_users(con)
  DBI::dbExecute(con, "UPDATE users SET active = 1 WHERE id = 2")

  d <- dolt_table_diff(con, "users", from = "HEAD", to = "WORKING")
  expect_true(any(grepl("^(to|from)_commit", names(d))))  # present in the raw diff

  tbl <- ns$doltlite_pane_diff_table(d)
  cols <- names(tbl$x$data)
  expect_identical(cols[[1]], "diff_type")
  expect_false(any(grepl("^(to|from)_commit", cols)))
  expect_true(all(c("to_active", "from_active") %in% cols))
})

test_that("table builders handle the empty cases", {
  skip_if_not_installed("DT")
  empty_diff <- ns$doltlite_pane_diff_table(NULL)
  expect_s3_class(empty_diff, "datatables")
  expect_identical(names(empty_diff$x$data), "No differences")

  empty_log <- ns$doltlite_pane_log_table(NULL)
  expect_s3_class(empty_log, "datatables")
  expect_identical(names(empty_log$x$data), "No commits yet")
})

test_that("log table abbreviates the commit hash", {
  skip_if_not_installed("DT")
  con <- local_dolt()
  seed_users(con, commit_message = "seeded")

  tbl <- ns$doltlite_pane_log_table(dolt_log(con))
  expect_identical(names(tbl$x$data),
                   c("commit", "date", "committer", "message"))
  expect_true(all(nchar(tbl$x$data$commit) == 8L))
  expect_true("seeded" %in% tbl$x$data$message)
})

# ---- merge state machine -------------------------------------------------
#
# Each branch of doltlite_pane_do_merge() corresponds to a measured DoltLite
# behaviour, so each is pinned here.

diverge <- function(con, conflict) {
  DBI::dbExecute(con, "CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)")
  DBI::dbExecute(con, "INSERT INTO t VALUES (1,'base'),(2,'keep')")
  dolt_commit(con, "base")
  dolt_checkout(con, "feature", create = TRUE)
  DBI::dbExecute(con, "UPDATE t SET v = 'feature-side' WHERE id = 1")
  dolt_commit(con, "feature edit")
  dolt_checkout(con, "main")
  if (conflict) {
    DBI::dbExecute(con, "UPDATE t SET v = 'main-side' WHERE id = 1")
    dolt_commit(con, "main edit")
  }
  invisible(con)
}

test_that("a clean merge completes and leaves no transaction open", {
  con <- local_dolt()
  diverge(con, conflict = FALSE)

  res <- ns$doltlite_pane_do_merge(con, "feature")
  expect_identical(res$state, "merged")
  # A clean merge ends the transaction itself; committing again would raise.
  expect_false(ns$doltlite_in_transaction(con))
  expect_identical(
    DBI::dbGetQuery(con, "SELECT v FROM t WHERE id = 1")$v, "feature-side")
})

test_that("a conflicting merge stays open with conflicts to resolve", {
  con <- local_dolt()
  diverge(con, conflict = TRUE)

  res <- ns$doltlite_pane_do_merge(con, "feature")
  expect_identical(res$state, "conflicted")
  expect_true(ns$doltlite_in_transaction(con))
  expect_identical(nrow(dolt_conflicts(con)), 1L)

  ns$doltlite_pane_abort_merge(con)
})

test_that("aborting a conflicted merge restores the pre-merge state", {
  con <- local_dolt()
  diverge(con, conflict = TRUE)
  ns$doltlite_pane_do_merge(con, "feature")

  ns$doltlite_pane_abort_merge(con)
  expect_false(ns$doltlite_in_transaction(con))
  expect_identical(nrow(dolt_conflicts(con)), 0L)
  expect_identical(
    DBI::dbGetQuery(con, "SELECT v FROM t WHERE id = 1")$v, "main-side")
  expect_identical(as.integer(dolt_merge_status(con)$is_merging), 0L)
})

test_that("resolving and committing finishes the merge", {
  con <- local_dolt()
  diverge(con, conflict = TRUE)
  ns$doltlite_pane_do_merge(con, "feature")

  dolt_conflicts_resolve(con, "theirs")
  expect_identical(nrow(dolt_conflicts(con)), 0L)
  dolt_commit(con, "Merge branch 'feature'")

  expect_false(ns$doltlite_in_transaction(con))
  expect_identical(
    DBI::dbGetQuery(con, "SELECT v FROM t WHERE id = 1")$v, "feature-side")
  expect_identical(dolt_log(con)$message[[1]], "Merge branch 'feature'")
})

test_that("a dirty working set blocks the merge without opening a transaction", {
  con <- local_dolt()
  diverge(con, conflict = FALSE)
  DBI::dbExecute(con, "INSERT INTO t VALUES (9, 'uncommitted')")

  res <- ns$doltlite_pane_do_merge(con, "feature")
  expect_identical(res$state, "blocked")
  expect_match(res$message, "uncommitted changes")
  # The guard must not leave a transaction behind: DoltLite's own refusal does.
  expect_false(ns$doltlite_in_transaction(con))
})

test_that("an already-open transaction blocks the merge", {
  con <- local_dolt()
  diverge(con, conflict = FALSE)

  DBI::dbBegin(con)
  res <- ns$doltlite_pane_do_merge(con, "feature")
  expect_identical(res$state, "blocked")
  expect_match(res$message, "transaction is already open")
  expect_true(ns$doltlite_in_transaction(con))
  DBI::dbRollback(con)
})

test_that("merging a branch that does not exist fails cleanly", {
  con <- local_dolt()
  diverge(con, conflict = FALSE)

  res <- ns$doltlite_pane_do_merge(con, "no-such-branch")
  expect_identical(res$state, "failed")
  # The error path must unwind the transaction it opened.
  expect_false(ns$doltlite_in_transaction(con))
})

test_that("conflict detail returns rows for one table", {
  skip_if_not_installed("DT")
  con <- local_dolt()
  diverge(con, conflict = TRUE)
  ns$doltlite_pane_do_merge(con, "feature")

  detail <- ns$doltlite_pane_conflict_detail(con)
  expect_true(all(c("base_v", "our_v", "their_v") %in% names(detail)))

  tbl <- ns$doltlite_pane_conflicts_table(detail)
  expect_s3_class(tbl, "datatables")
  # Internal join keys are not worth the width.
  expect_false(any(c("from_root_ish", "dolt_conflict_id") %in%
                     names(tbl$x$data)))

  ns$doltlite_pane_abort_merge(con)
  expect_null(ns$doltlite_pane_conflict_detail(con))
})

# ---- two conflicted tables ----------------------------------------------
#
# The case the picker exists for. Before it, this fell back to a per-table
# summary, so the more there was to look at the less was shown.

diverge_two <- function(con) {
  DBI::dbExecute(con, "CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)")
  DBI::dbExecute(con, "CREATE TABLE u (id INTEGER PRIMARY KEY, w TEXT)")
  DBI::dbExecute(con, "INSERT INTO t VALUES (1,'base')")
  DBI::dbExecute(con, "INSERT INTO u VALUES (1,'base')")
  dolt_commit(con, "base")
  dolt_checkout(con, "feature", create = TRUE)
  DBI::dbExecute(con, "UPDATE t SET v = 'theirs' WHERE id = 1")
  DBI::dbExecute(con, "UPDATE u SET w = 'theirs' WHERE id = 1")
  dolt_commit(con, "feature edits")
  dolt_checkout(con, "main")
  DBI::dbExecute(con, "UPDATE t SET v = 'ours' WHERE id = 1")
  DBI::dbExecute(con, "UPDATE u SET w = 'ours' WHERE id = 1")
  dolt_commit(con, "main edits")
  invisible(con)
}

test_that("both conflicted tables are listed, with their counts", {
  con <- local_dolt()
  diverge_two(con)
  expect_identical(ns$doltlite_pane_do_merge(con, "feature")$state,
                   "conflicted")

  cf <- ns$doltlite_pane_conflicted(con)
  expect_setequal(cf$table, c("t", "u"))
  expect_true(all(cf$n == 1L))

  ns$doltlite_pane_abort_merge(con)
})

test_that("detail follows the selected table rather than collapsing", {
  con <- local_dolt()
  diverge_two(con)
  ns$doltlite_pane_do_merge(con, "feature")

  dt <- ns$doltlite_pane_conflict_detail(con, "t")
  du <- ns$doltlite_pane_conflict_detail(con, "u")
  # Each answers with that table's own columns, not a shared summary.
  expect_true("our_v" %in% names(dt))
  expect_true("our_w" %in% names(du))
  expect_false("our_w" %in% names(dt))

  ns$doltlite_pane_abort_merge(con)
})

test_that("an unknown or missing table falls back to the first conflicted one", {
  con <- local_dolt()
  diverge_two(con)
  ns$doltlite_pane_do_merge(con, "feature")

  first <- ns$doltlite_pane_conflicted(con)$table[[1L]]
  expect_identical(names(ns$doltlite_pane_conflict_detail(con, "no-such")),
                   names(ns$doltlite_pane_conflict_detail(con, first)))
  expect_identical(names(ns$doltlite_pane_conflict_detail(con, NULL)),
                   names(ns$doltlite_pane_conflict_detail(con, first)))

  ns$doltlite_pane_abort_merge(con)
})

test_that("resolving one table leaves the other conflicted", {
  con <- local_dolt()
  diverge_two(con)
  ns$doltlite_pane_do_merge(con, "feature")

  dolt_conflicts_resolve(con, "theirs", tables = "t")
  left <- ns$doltlite_pane_conflicted(con)
  expect_identical(left$table, "u")

  dolt_conflicts_resolve(con, "ours", tables = "u")
  expect_identical(nrow(ns$doltlite_pane_conflicted(con)), 0L)

  dolt_commit(con, "Merge branch 'feature'")
  # Each table kept the side it was resolved with, independently.
  expect_identical(DBI::dbGetQuery(con, "SELECT v FROM t")$v, "theirs")
  expect_identical(DBI::dbGetQuery(con, "SELECT w FROM u")$w, "ours")
})

test_that("conflicted() has a stable shape when there is nothing", {
  con <- local_dolt()
  seed_users(con)
  cf <- ns$doltlite_pane_conflicted(con)
  expect_s3_class(cf, "data.frame")
  expect_identical(nrow(cf), 0L)
  expect_identical(names(cf), c("table", "n"))
})

test_that("branches table marks the connection's current branch", {
  skip_if_not_installed("DT")
  con <- local_dolt()
  seed_users(con)
  dolt_checkout(con, "feature", create = TRUE)

  tbl <- ns$doltlite_pane_branches_table(dolt_branches(con),
                                         active_branch(con))
  marked <- grep("\\*$", tbl$x$data$branch, value = TRUE)
  expect_length(marked, 1L)
  expect_match(marked, "^feature")
})
