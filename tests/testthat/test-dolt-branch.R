test_that("branches can be created, listed and checked out", {
  con <- local_dolt()
  seed_users(con)

  expect_identical(active_branch(con), "main")
  expect_identical(dolt_active_branch(con), "main")

  dolt_branch(con, "experiment")
  expect_setequal(dolt_branches(con)$name, c("main", "experiment"))

  dolt_checkout(con, "experiment")
  expect_identical(active_branch(con), "experiment")

  dolt_checkout(con, "main")
  expect_identical(active_branch(con), "main")
})

test_that("dolt_checkout can create and switch in one step", {
  con <- local_dolt()
  seed_users(con)
  dolt_checkout(con, "feature", create = TRUE)
  expect_identical(active_branch(con), "feature")
})

test_that("a branch can be deleted", {
  con <- local_dolt()
  seed_users(con)
  dolt_branch(con, "scratch")
  expect_true("scratch" %in% dolt_branches(con)$name)
  dolt_branch(con, "scratch", delete = TRUE)
  expect_false("scratch" %in% dolt_branches(con)$name)
})

test_that("a non-conflicting merge brings changes back to main", {
  con <- local_dolt()
  seed_users(con)

  dolt_checkout(con, "experiment", create = TRUE)
  DBI::dbExecute(con, "UPDATE users SET active = 1 WHERE id = 2")
  dolt_commit(con, "activate bob")

  dolt_checkout(con, "main")
  expect_equal(DBI::dbGetQuery(con, "SELECT active FROM users WHERE id = 2")$active, 0L)

  result <- dolt_merge(con, "experiment")
  expect_match(result, "^[0-9a-f]{40}$")
  expect_equal(DBI::dbGetQuery(con, "SELECT active FROM users WHERE id = 2")$active, 1L)
})

test_that("branches isolate uncommitted-to-committed work", {
  con <- local_dolt()
  seed_users(con)

  dolt_checkout(con, "side", create = TRUE)
  DBI::dbExecute(con, "INSERT INTO users VALUES (3, 'cleo', 1)")
  dolt_commit(con, "add cleo")
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM users")$n, 3)

  dolt_checkout(con, "main")
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM users")$n, 2)
})

test_that("conflicting edits surface as conflicts and can be resolved", {
  con <- local_dolt()
  seed_users(con)

  dolt_checkout(con, "theirs", create = TRUE)
  DBI::dbExecute(con, "UPDATE users SET nm = 'THEIRS' WHERE id = 1")
  dolt_commit(con, "theirs")

  dolt_checkout(con, "main")
  DBI::dbExecute(con, "UPDATE users SET nm = 'OURS' WHERE id = 1")
  dolt_commit(con, "ours")

  # Conflicts live only inside the transaction that produced them, so the
  # merge has to run in one for there to be anything to resolve.
  DBI::dbBegin(con)
  result <- dolt_merge(con, "theirs")
  expect_match(result, "conflict")

  conflicts <- dolt_conflicts(con)
  expect_true(nrow(conflicts) >= 1L)

  # A commit is refused while conflicts remain.
  expect_error(dolt_commit(con, "should not work"), "conflict")

  dolt_conflicts_resolve(con, "ours")
  expect_equal(nrow(dolt_conflicts(con)), 0L)
  # dolt_commit() also ends the SQL transaction, so there is nothing left for
  # dbCommit() to do.
  dolt_commit(con, "merge theirs, keeping ours")
  expect_error(DBI::dbCommit(con), "no transaction")

  expect_equal(DBI::dbGetQuery(con, "SELECT nm FROM users WHERE id = 1")$nm, "OURS")
})

test_that("a conflicting merge in autocommit mode is rolled back whole", {
  # DoltLite refuses to leave a conflicted working set on disk, so an
  # autocommit merge that conflicts errors instead of reporting conflicts.
  con <- local_dolt()
  seed_users(con)

  dolt_checkout(con, "theirs", create = TRUE)
  DBI::dbExecute(con, "UPDATE users SET nm = 'THEIRS' WHERE id = 1")
  dolt_commit(con, "theirs")

  dolt_checkout(con, "main")
  DBI::dbExecute(con, "UPDATE users SET nm = 'OURS' WHERE id = 1")
  dolt_commit(con, "ours")

  expect_error(dolt_merge(con, "theirs"), "conflict")
  expect_equal(nrow(dolt_conflicts(con)), 0L)
  expect_equal(DBI::dbGetQuery(con, "SELECT nm FROM users WHERE id = 1")$nm, "OURS")
})

test_that("merge status is reported", {
  con <- local_dolt()
  seed_users(con)
  status <- dolt_merge_status(con)
  expect_equal(nrow(status), 1L)
  expect_equal(status$is_merging, 0L)
})

test_that("tags can be created and listed", {
  con <- local_dolt()
  seed_users(con)
  dolt_tag(con, "v1.0")
  expect_true("v1.0" %in% dolt_tags(con)$tag_name |
                "v1.0" %in% unlist(dolt_tags(con), use.names = FALSE))
  dolt_tag(con, "v1.0", delete = TRUE)
  expect_false("v1.0" %in% unlist(dolt_tags(con), use.names = FALSE))
})

test_that("merge base is the common ancestor", {
  con <- local_dolt()
  seed_users(con)
  base <- dolt_hashof(con, "main")

  dolt_checkout(con, "side", create = TRUE)
  DBI::dbExecute(con, "INSERT INTO users VALUES (3, 'cleo', 1)")
  dolt_commit(con, "side work")

  dolt_checkout(con, "main")
  DBI::dbExecute(con, "INSERT INTO users VALUES (4, 'dee', 1)")
  dolt_commit(con, "main work")

  expect_identical(
    dolt_merge_base(con, dolt_hashof(con, "main"), dolt_hashof(con, "side")),
    base
  )
})
