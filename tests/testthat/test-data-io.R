test_that("dbWriteTable round-trips a data frame", {
  con <- local_dolt()
  df <- data.frame(
    i = 1:3,
    d = c(1.5, 2.5, NA),
    s = c("a", NA, "c"),
    stringsAsFactors = FALSE
  )
  DBI::dbWriteTable(con, "t", df)

  expect_true(DBI::dbExistsTable(con, "t"))
  expect_identical(DBI::dbListFields(con, "t"), c("i", "d", "s"))
  expect_equal(DBI::dbReadTable(con, "t"), df)
})

test_that("dbWriteTable does not insert a phantom row", {
  # Regression test: binding parameters used to run the INSERT once with
  # everything bound to NULL before the real rows were bound.
  con <- local_dolt()
  DBI::dbWriteTable(con, "t", data.frame(x = 1:3))
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM t")$n, 3)
  expect_equal(DBI::dbReadTable(con, "t")$x, 1:3)
})

test_that("overwrite and append behave", {
  con <- local_dolt()
  DBI::dbWriteTable(con, "t", data.frame(x = 1:2))
  expect_error(DBI::dbWriteTable(con, "t", data.frame(x = 3L)), "already exists")

  DBI::dbWriteTable(con, "t", data.frame(x = 3:4), append = TRUE)
  expect_equal(DBI::dbReadTable(con, "t")$x, 1:4)

  DBI::dbWriteTable(con, "t", data.frame(x = 9L), overwrite = TRUE)
  expect_equal(DBI::dbReadTable(con, "t")$x, 9L)

  expect_error(
    DBI::dbWriteTable(con, "t", data.frame(x = 1L), overwrite = TRUE, append = TRUE),
    "cannot both be TRUE"
  )
})

test_that("a table written without a primary key keeps its rowid", {
  # The common dbWriteTable path must stay ordinary SQLite: only a
  # non-INTEGER PRIMARY KEY makes a table clustered.
  con <- local_dolt()
  DBI::dbWriteTable(con, "t", data.frame(a = 1L, b = "x", stringsAsFactors = FALSE))
  expect_equal(DBI::dbGetQuery(con, "SELECT rowid FROM t")$rowid, 1L)
})

test_that("a non-INTEGER primary key becomes clustered and NOT NULL", {
  con <- local_dolt()
  DBI::dbCreateTable(con, "k", c(k = "TEXT", v = "REAL"),
                     field.types = c(k = "TEXT PRIMARY KEY"))
  info <- DBI::dbGetQuery(con, "SELECT name, \"notnull\", pk FROM pragma_table_info('k')")
  expect_equal(info$notnull[info$name == "k"], 1L)

  # There is no stored rowid on such a table.
  expect_error(DBI::dbExecute(con, "INSERT INTO k(rowid, k, v) VALUES (1,'a',1.0)"),
               "no column named rowid")
  expect_error(DBI::dbExecute(con, "INSERT INTO k(k, v) VALUES (NULL, 1.0)"),
               "NOT NULL")
})

test_that("blobs round-trip as raw vectors", {
  con <- local_dolt()
  DBI::dbExecute(con, "CREATE TABLE b (id INTEGER, payload BLOB)")
  DBI::dbExecute(con, "INSERT INTO b VALUES (?, ?)",
                 params = list(1L, list(as.raw(c(0, 255, 16)))))
  out <- DBI::dbReadTable(con, "b")
  expect_type(out$payload, "list")
  expect_identical(out$payload[[1]], as.raw(c(0, 255, 16)))
})

test_that("large integers come back as integer64 by default", {
  con <- local_dolt()
  out <- DBI::dbGetQuery(con, "SELECT 10000000000 AS big")
  expect_s3_class(out$big, "integer64")
  expect_identical(as.character(out$big), "10000000000")
})

test_that("the bigint option is honoured", {
  path <- tempfile(fileext = ".db")
  on.exit(unlink(path), add = TRUE)
  for (mode in c("numeric", "character")) {
    con <- DBI::dbConnect(Doltlite(), path, bigint = mode)
    out <- DBI::dbGetQuery(con, "SELECT 10000000000 AS big")
    if (mode == "numeric") {
      expect_equal(out$big, 1e10)
    } else {
      expect_identical(out$big, "10000000000")
    }
    DBI::dbDisconnect(con)
  }
})

test_that("mixed-type columns widen rather than truncate", {
  con <- local_dolt()
  out <- DBI::dbGetQuery(
    con, "SELECT 1 AS x UNION ALL SELECT 2.5 UNION ALL SELECT 3"
  )
  expect_type(out$x, "double")
  expect_equal(sort(out$x), c(1, 2.5, 3))
})

test_that("an all-NULL column comes back as logical NA", {
  con <- local_dolt()
  out <- DBI::dbGetQuery(con, "SELECT NULL AS x UNION ALL SELECT NULL")
  expect_type(out$x, "logical")
  expect_true(all(is.na(out$x)))
})

test_that("dbColumnInfo reports types before the first fetch", {
  con <- local_dolt()
  res <- DBI::dbSendQuery(con, "SELECT CAST(1 AS INTEGER) AS i, 'x' AS s, 1.5 AS d")
  info <- DBI::dbColumnInfo(res)
  expect_identical(info$name, c("i", "s", "d"))
  expect_identical(info$type, c("integer", "character", "numeric"))
  DBI::dbClearResult(res)
})

test_that("parameters bind by position and by name", {
  con <- local_dolt()
  DBI::dbWriteTable(con, "t", data.frame(x = 1:5))
  expect_equal(DBI::dbGetQuery(con, "SELECT x FROM t WHERE x > ?", list(3))$x, 4:5)
  expect_equal(
    DBI::dbGetQuery(con, "SELECT x FROM t WHERE x > :lo", list(lo = 3))$x,
    4:5
  )
})

test_that("a query bound to several parameter sets returns them all", {
  con <- local_dolt()
  out <- DBI::dbGetQuery(con, "SELECT ? + 1 AS a", params = list(c(0, 1, 2)))
  expect_equal(out$a, c(1, 2, 3))
})

test_that("fetching in chunks tracks completion", {
  con <- local_dolt()
  DBI::dbWriteTable(con, "t", data.frame(x = 1:5))
  res <- DBI::dbSendQuery(con, "SELECT x FROM t ORDER BY x")

  expect_equal(nrow(DBI::dbFetch(res, 2)), 2)
  expect_false(DBI::dbHasCompleted(res))
  expect_equal(nrow(DBI::dbFetch(res, -1)), 3)
  expect_true(DBI::dbHasCompleted(res))
  expect_equal(DBI::dbGetRowCount(res), 5)
  DBI::dbClearResult(res)
})

test_that("dbRemoveTable honours temporary and fail_if_missing", {
  con <- local_dolt()
  DBI::dbWriteTable(con, "t", data.frame(a = 1))
  DBI::dbCreateTable(con, "t", data.frame(b = 2), temporary = TRUE)

  DBI::dbRemoveTable(con, "t", temporary = TRUE)
  expect_error(DBI::dbRemoveTable(con, "t", temporary = TRUE), "no such temporary")
  # The permanent table is untouched.
  expect_equal(DBI::dbReadTable(con, "t"), data.frame(a = 1))

  expect_false(DBI::dbRemoveTable(con, "nope", fail_if_missing = FALSE))
  expect_error(DBI::dbRemoveTable(con, "nope"), "no such table")
})

test_that("a statement that fails during preparation leaves no dangling result", {
  # Regression test for a crash: the result registered itself with the
  # connection before running, and a statement that raised (a constraint
  # violation, say) skipped its own destructor, leaving the connection holding
  # a pointer to freed storage. Disconnecting then walked into it.
  con <- local_dolt()
  DBI::dbExecute(con, "CREATE TABLE k (k TEXT PRIMARY KEY, v REAL)")

  for (i in 1:20) {
    expect_error(DBI::dbExecute(con, "INSERT INTO k(k, v) VALUES (NULL, 1.0)"))
    expect_error(DBI::dbExecute(con, "INSERT INTO nosuchtable VALUES (1)"))
  }
  gc()

  expect_true(DBI::dbIsValid(con))
  DBI::dbDisconnect(con)
  expect_false(DBI::dbIsValid(con))
})
