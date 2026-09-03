test_that("the driver reports the DoltLite prolly engine", {
  expect_identical(doltlite_engine(), "prolly")
  expect_match(doltlite_version(), "^[0-9]+\\.[0-9]+")
})

test_that("connecting and disconnecting work", {
  con <- local_dolt()
  expect_s4_class(con, "DoltliteConnection")
  expect_true(DBI::dbIsValid(con))

  DBI::dbDisconnect(con)
  expect_false(DBI::dbIsValid(con))
  expect_warning(DBI::dbDisconnect(con), "already been disconnected")
})

test_that("an in-memory database works but is not version controlled", {
  con <- DBI::dbConnect(Doltlite(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  expect_identical(DBI::dbGetQuery(con, "SELECT doltlite_engine() AS e")$e, "prolly")
})

test_that("an anonymous temporary database falls back to the B-tree engine", {
  # Documented DoltLite behaviour, and the reason the test helper always uses a
  # real file: version control is unavailable on such a database.
  con <- DBI::dbConnect(Doltlite(), "")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  expect_identical(DBI::dbGetQuery(con, "SELECT doltlite_engine() AS e")$e, "orig")
  expect_error(dolt_status(con), "needs a DoltLite-format database")
})

test_that("dbGetInfo reports the branch and engine", {
  con <- local_dolt()
  info <- DBI::dbGetInfo(con)
  expect_identical(info$branch, "main")
  expect_identical(info$doltlite.engine, "prolly")
  expect_false(info$readonly)
})

test_that("branch= selects a branch and rejects one that does not exist", {
  con <- local_dolt()
  path <- DBI::dbGetInfo(con)$dbname
  seed_users(con)
  dolt_branch(con, "experiment")
  DBI::dbDisconnect(con)

  con2 <- DBI::dbConnect(Doltlite(), path, branch = "experiment")
  on.exit(DBI::dbDisconnect(con2), add = TRUE)
  expect_identical(active_branch(con2), "experiment")

  expect_error(
    DBI::dbConnect(Doltlite(), path, branch = "no-such-branch"),
    "no-such-branch"
  )
})

test_that("branch= is rejected where DoltLite would ignore it", {
  expect_error(DBI::dbConnect(Doltlite(), ":memory:", branch = "x"),
               "not meaningful")
  expect_error(DBI::dbConnect(Doltlite(), "some.db@rev", branch = "x"),
               "either that or")
})

test_that("transactions are SQL transactions, not Dolt commits", {
  con <- local_dolt()
  seed_users(con)

  DBI::dbBegin(con)
  DBI::dbExecute(con, "INSERT INTO users VALUES (3, 'cleo', 1)")
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM users")$n, 3)
  DBI::dbRollback(con)
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM users")$n, 2)

  DBI::dbBegin(con)
  DBI::dbExecute(con, "INSERT INTO users VALUES (3, 'cleo', 1)")
  DBI::dbCommit(con)
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM users")$n, 3)

  # Committing the SQL transaction leaves the change uncommitted in Dolt.
  expect_equal(nrow(dolt_status(con)), 1L)
})

test_that("nesting and stray transaction verbs are refused", {
  con <- local_dolt()
  DBI::dbBegin(con)
  expect_error(DBI::dbBegin(con), "already open")
  DBI::dbRollback(con)
  expect_error(DBI::dbCommit(con), "no transaction")
  expect_error(DBI::dbRollback(con), "no transaction")
})

test_that("double-quoted identifiers are not treated as string literals", {
  con <- local_dolt()
  # Stock SQLite would return the string "b" here rather than erroring.
  expect_error(DBI::dbGetQuery(con, 'SELECT "b" FROM (SELECT 1 AS "a")'))
})

test_that("only one statement per call is accepted", {
  con <- local_dolt()
  expect_error(
    DBI::dbExecute(con, "CREATE TABLE a(x INT); CREATE TABLE b(x INT)"),
    "more than one statement"
  )
})
