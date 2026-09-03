test_that("dolt_config sets and reads the committer identity", {
  con <- local_dolt(configure = FALSE)
  dolt_config(con, user.name = "Ada Lovelace", user.email = "ada@example.com")
  expect_identical(dolt_config(con, "user.name"), "Ada Lovelace")
  expect_identical(dolt_config(con, "user.email"), "ada@example.com")
  expect_error(dolt_config(con), "supply `key`")
})

test_that("a fresh database starts with one commit and a clean status", {
  con <- local_dolt()
  expect_equal(nrow(dolt_status(con)), 0L)
  expect_equal(nrow(dolt_log(con)), 1L)
  expect_identical(dolt_log(con)$message, "Initialize data repository")
})

test_that("status reports uncommitted work and clears after committing", {
  con <- local_dolt()
  DBI::dbExecute(con, "CREATE TABLE t (id INTEGER PRIMARY KEY)")
  st <- dolt_status(con)
  expect_identical(st$table_name, "t")
  expect_identical(st$status, "new table")

  hash <- dolt_commit(con, "add t")
  expect_match(hash, "^[0-9a-f]{40}$")
  expect_equal(nrow(dolt_status(con)), 0L)
})

test_that("dolt_log records the configured author and message", {
  con <- local_dolt()
  seed_users(con, "initial load")
  log <- dolt_log(con)
  expect_identical(log$message[[1]], "initial load")
  expect_identical(log$committer[[1]], "Test User")
  expect_identical(log$email[[1]], "test@example.com")
})

test_that("commit messages containing quotes and semicolons are safe", {
  # Arguments are bound as parameters rather than interpolated, so this is a
  # value, not SQL.
  con <- local_dolt()
  seed_users(con)
  msg <- "it's a '; DROP TABLE users; -- message"
  DBI::dbExecute(con, "INSERT INTO users VALUES (3, 'cleo', 1)")
  dolt_commit(con, msg)

  expect_identical(dolt_log(con)$message[[1]], msg)
  expect_true(DBI::dbExistsTable(con, "users"))
})

test_that("branch names containing quotes are safe too", {
  con <- local_dolt()
  seed_users(con)
  dolt_branch(con, "odd'name")
  expect_true("odd'name" %in% dolt_branches(con)$name)
})

test_that("--author overrides the configured identity for one commit", {
  con <- local_dolt()
  seed_users(con)
  DBI::dbExecute(con, "INSERT INTO users VALUES (3, 'cleo', 1)")
  dolt_commit(con, "by someone else", author = "Grace <grace@example.com>")
  expect_identical(dolt_log(con)$committer[[1]], "Grace")
})

test_that("dolt_add stages named tables", {
  con <- local_dolt()
  DBI::dbExecute(con, "CREATE TABLE a (id INTEGER PRIMARY KEY)")
  DBI::dbExecute(con, "CREATE TABLE b (id INTEGER PRIMARY KEY)")
  dolt_add(con, "a")
  st <- dolt_status(con)
  expect_equal(st$staged[st$table_name == "a"], 1L)
  expect_equal(st$staged[st$table_name == "b"], 0L)
})

test_that("dolt_reset discards or unstages work", {
  con <- local_dolt()
  seed_users(con)
  DBI::dbExecute(con, "INSERT INTO users VALUES (3, 'cleo', 1)")
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM users")$n, 3)

  dolt_reset(con, "hard")
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM users")$n, 2)
  expect_equal(nrow(dolt_status(con)), 0L)
})

test_that("dolt_revert undoes a commit with a new commit", {
  con <- local_dolt()
  seed_users(con)
  DBI::dbExecute(con, "INSERT INTO users VALUES (3, 'cleo', 1)")
  target <- dolt_commit(con, "add cleo")

  dolt_revert(con, target)
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM users")$n, 2)
  expect_match(dolt_log(con)$message[[1]], "^Revert")
})

test_that("hashes are stable 40-character hex", {
  con <- local_dolt()
  seed_users(con)
  expect_match(dolt_hashof(con, "main"), "^[0-9a-f]{40}$")
  expect_match(dolt_hashof_table(con, "users"), "^[0-9a-f]{40}$")
  expect_match(dolt_hashof_db(con), "^[0-9a-f]{40}$")
})

test_that("version-control verbs reject an invalid function name", {
  con <- local_dolt()
  expect_error(dolt_scalar(con, "dolt_commit; DROP TABLE x"), "invalid function name")
  expect_error(dolt_table(con, "dolt_log WHERE 1=1"), "invalid relation name")
})
