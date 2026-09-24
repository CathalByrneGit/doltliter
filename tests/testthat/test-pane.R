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

  con <- DBI::dbConnect(doltliter::Doltlite(), "")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  expect_error(doltliter::dolt_pane(con), "needs a DoltLite-format database")
})

test_that("dolt_pane() reports missing Suggests rather than failing obscurely", {
  # Simulate shiny being absent by calling the guard with a stub in place.
  local_mocked_bindings(
    requireNamespace = function(package, ...) {
      if (package %in% c("shiny", "miniUI")) FALSE else TRUE
    },
    .package = "base"
  )
  expect_error(ns$doltlite_require_shiny(), "shiny and miniUI")
})

# The reactive logic is the part worth testing: shiny::testServer runs it
# without a browser, so the commit guard and the refresh cycle are covered
# rather than just the helpers around them.

test_that("the UI builds for a real connection", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("miniUI")
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
