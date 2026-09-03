test_that("dolt_diff lists changed tables per commit", {
  con <- local_dolt()
  seed_users(con)

  d <- dolt_diff(con)
  expect_true("users" %in% d$table_name)
  expect_true(all(c("commit_hash", "data_change", "schema_change") %in% names(d)))

  expect_true(all(dolt_diff(con, "users")$table_name == "users"))
})

test_that("uncommitted changes appear under the WORKING pseudo-commit", {
  con <- local_dolt()
  seed_users(con)
  DBI::dbExecute(con, "INSERT INTO users VALUES (3, 'cleo', 1)")
  expect_true("WORKING" %in% dolt_diff(con, "users")$commit_hash)
})

test_that("dolt_table_diff compares two refs", {
  con <- local_dolt()
  seed_users(con)

  dolt_checkout(con, "experiment", create = TRUE)
  DBI::dbExecute(con, "UPDATE users SET active = 1 WHERE id = 2")
  dolt_commit(con, "activate bob")

  d <- dolt_table_diff(con, "users", from = "main", to = "experiment")
  expect_equal(nrow(d), 1L)
  expect_identical(d$diff_type, "modified")
  expect_equal(d$to_id, 2L)
  expect_equal(d$from_active, 0L)
  expect_equal(d$to_active, 1L)
})

test_that("dolt_table_diff accepts a range and rejects mixed forms", {
  con <- local_dolt()
  seed_users(con)
  dolt_checkout(con, "experiment", create = TRUE)
  DBI::dbExecute(con, "UPDATE users SET active = 1 WHERE id = 2")
  dolt_commit(con, "activate bob")

  expect_equal(nrow(dolt_table_diff(con, "users", range = "main..experiment")), 1L)
  expect_error(
    dolt_table_diff(con, "users", from = "main", range = "main..experiment"),
    "either"
  )
  expect_error(dolt_table_diff(con, "users", from = "main"), "both")
})

test_that("working changes diff against HEAD", {
  con <- local_dolt()
  seed_users(con)
  DBI::dbExecute(con, "UPDATE users SET nm = 'ADA' WHERE id = 1")
  d <- dolt_table_diff(con, "users", from = "HEAD", to = "WORKING")
  expect_identical(d$diff_type, "modified")
  expect_identical(d$to_nm, "ADA")
})

test_that("dolt_diff_stat and dolt_diff_summary report per-table changes", {
  con <- local_dolt()
  seed_users(con)
  DBI::dbExecute(con, "INSERT INTO users VALUES (3, 'cleo', 1)")
  dolt_commit(con, "add cleo")

  expect_true(nrow(dolt_diff_stat(con, "HEAD~1", "HEAD")) >= 1L)
  expect_true(nrow(dolt_diff_summary(con, "HEAD~1", "HEAD")) >= 1L)
})

test_that("dolt_history returns every version of a row", {
  con <- local_dolt()
  seed_users(con)
  DBI::dbExecute(con, "UPDATE users SET nm = 'ADA' WHERE id = 1")
  dolt_commit(con, "rename ada")

  h <- dolt_history(con, "users")
  expect_true(nrow(h) >= 3L)
  expect_true("ADA" %in% h$nm)
  expect_true("ada" %in% h$nm)
})

test_that("dolt_at reads a table as it was at a revision", {
  con <- local_dolt()
  seed_users(con)
  first <- dolt_hashof(con, "HEAD")
  DBI::dbExecute(con, "UPDATE users SET nm = 'ADA' WHERE id = 1")
  dolt_commit(con, "rename ada")

  expect_identical(dolt_at(con, "users", first)$nm[[1]], "ada")
  expect_identical(DBI::dbReadTable(con, "users")$nm[[1]], "ADA")
})

test_that("dolt_blame attributes rows to commits", {
  con <- local_dolt()
  seed_users(con)
  b <- dolt_blame(con, "users")
  expect_equal(nrow(b), 2L)
  expect_true(all(b$committer == "Test User"))
})

test_that("dolt_blame needs a primary key", {
  # DoltLite behaviour, worth pinning: a table with no primary key has no
  # stable row identity to attribute changes to.
  con <- local_dolt()
  DBI::dbWriteTable(con, "nopk", data.frame(x = 1:2))
  dolt_commit(con, "add nopk")
  expect_error(dolt_blame(con, "nopk"), "no primary key")
})

test_that("dolt_patch produces executable statements", {
  con <- local_dolt()
  seed_users(con)
  DBI::dbExecute(con, "INSERT INTO users VALUES (3, 'cleo', 1)")
  dolt_commit(con, "add cleo")

  p <- dolt_patch(con, "HEAD~1", "HEAD")
  expect_true(nrow(p) >= 1L)
  expect_true("statement" %in% names(p))
})

test_that("dolt_schemas tracks views", {
  con <- local_dolt()
  seed_users(con)
  DBI::dbExecute(con, "CREATE VIEW active_users AS SELECT * FROM users WHERE active = 1")
  dolt_commit(con, "add view")

  s <- dolt_schemas(con)
  expect_true("active_users" %in% s$name)
})
