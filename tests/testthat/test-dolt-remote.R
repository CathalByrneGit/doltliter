test_that("a fresh database has no remotes", {
  con <- local_dolt()
  expect_equal(nrow(dolt_remotes(con)), 0L)
  expect_equal(nrow(dolt_remote(con)), 0L)
})

test_that("a filesystem remote round-trips a push and a clone", {
  origin_path <- tempfile("doltliter-origin", fileext = ".db")
  clone_path <- tempfile("doltliter-clone", fileext = ".db")
  on.exit(unlink(c(origin_path, clone_path)), add = TRUE)

  # Build the origin database.
  origin <- DBI::dbConnect(Doltlite(), origin_path)
  dolt_config(origin, user.name = "Test User", user.email = "test@example.com")
  DBI::dbExecute(origin, "CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)")
  DBI::dbExecute(origin, "INSERT INTO t VALUES (1, 'one')")
  dolt_commit(origin, "seed origin")
  DBI::dbDisconnect(origin)

  # Clone it into a new database.
  clone <- DBI::dbConnect(Doltlite(), clone_path)
  on.exit(if (DBI::dbIsValid(clone)) DBI::dbDisconnect(clone), add = TRUE)
  dolt_clone(clone, paste0("file://", origin_path))

  expect_true(DBI::dbExistsTable(clone, "t"))
  expect_identical(DBI::dbReadTable(clone, "t")$v, "one")
  expect_identical(dolt_log(clone)$message[[1]], "seed origin")
  expect_true("origin" %in% dolt_remotes(clone)$name)
})

test_that("remotes can be added and removed", {
  con <- local_dolt()
  dolt_remote(con, "add", "upstream", "file:///tmp/nowhere.db")
  expect_true("upstream" %in% dolt_remotes(con)$name)

  dolt_remote(con, "remove", "upstream")
  expect_false("upstream" %in% dolt_remotes(con)$name)

  expect_error(dolt_remote(con, "add", "x"), "`url` is required")
  expect_error(dolt_remote(con, "add"), "`name` is required")
})

test_that("push and pull move commits between databases", {
  origin_path <- tempfile("doltliter-origin", fileext = ".db")
  work_path <- tempfile("doltliter-work", fileext = ".db")
  on.exit(unlink(c(origin_path, work_path)), add = TRUE)

  origin <- DBI::dbConnect(Doltlite(), origin_path)
  dolt_config(origin, user.name = "Test User", user.email = "test@example.com")
  DBI::dbExecute(origin, "CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)")
  DBI::dbExecute(origin, "INSERT INTO t VALUES (1, 'one')")
  dolt_commit(origin, "seed origin")
  DBI::dbDisconnect(origin)

  work <- DBI::dbConnect(Doltlite(), work_path)
  dolt_clone(work, paste0("file://", origin_path))
  dolt_config(work, user.name = "Test User", user.email = "test@example.com")
  DBI::dbExecute(work, "INSERT INTO t VALUES (2, 'two')")
  dolt_commit(work, "add two")
  dolt_push(work, "origin", "main")
  DBI::dbDisconnect(work)

  # The pushed commit is visible in the origin.
  origin2 <- DBI::dbConnect(Doltlite(), origin_path)
  on.exit(if (DBI::dbIsValid(origin2)) DBI::dbDisconnect(origin2), add = TRUE)
  expect_identical(dolt_log(origin2)$message[[1]], "add two")
  expect_equal(nrow(DBI::dbReadTable(origin2, "t")), 2L)
})
