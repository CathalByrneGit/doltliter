skip_if_not_installed("dplyr")
skip_if_not_installed("dbplyr")

test_that("dplyr::tbl and lazy queries work over a DoltLite connection", {
  con <- local_dolt()
  DBI::dbWriteTable(con, "users", data.frame(
    id = 1:5,
    nm = letters[1:5],
    active = c(1L, 0L, 1L, 1L, 0L),
    score = c(1, 2, 3, 4, 5),
    stringsAsFactors = FALSE
  ))

  tb <- dplyr::tbl(con, "users")
  out <- dplyr::collect(
    dplyr::arrange(
      dplyr::select(
        dplyr::filter(tb, active == 1),
        id, nm, score
      ),
      dplyr::desc(score)
    )
  )

  expect_equal(out$id, c(4L, 3L, 1L))
  expect_equal(out$score, c(4, 3, 1))
})

test_that("grouped summaries are pushed down to SQL", {
  con <- local_dolt()
  DBI::dbWriteTable(con, "users", data.frame(
    id = 1:5, active = c(1L, 0L, 1L, 1L, 0L), score = c(1, 2, 3, 4, 5)
  ))

  out <- dplyr::collect(
    dplyr::summarise(
      dplyr::group_by(dplyr::tbl(con, "users"), active),
      n = dplyr::n(),
      total = sum(score, na.rm = TRUE)
    )
  )
  out <- out[order(out$active), ]
  expect_equal(out$n, c(2L, 3L))
  expect_equal(out$total, c(7, 8))
})

test_that("the connection reports itself to dbplyr", {
  con <- local_dolt()
  desc <- dbplyr::db_connection_describe(con)
  expect_match(desc, "^doltlite ")
  expect_match(desc, "@main\\]$")
})

test_that("dbplyr treats the backend as second edition", {
  con <- local_dolt()
  expect_equal(dbplyr::dbplyr_edition(con), 2L)
})

test_that("SQLite-specific translations are used when available", {
  skip_if_not_installed("RSQLite")
  con <- local_dolt()
  DBI::dbWriteTable(con, "t", data.frame(id = 1:2, nm = c("a", "b"),
                                         stringsAsFactors = FALSE))
  sql <- dbplyr::sql_render(
    dplyr::mutate(dplyr::tbl(con, "t"), lbl = paste0(nm, "-", id))
  )
  # SQLite concatenates with ||, not CONCAT().
  expect_match(as.character(sql), "||", fixed = TRUE)
})

test_that("copy_to() and compute() create correctly named tables", {
  # Regression test. dbplyr's SQLite dialect quotes identifiers with
  # backticks, and the SQL() name it hands to dbCreateTable() arrives already
  # quoted. Only double quotes were being stripped, so copy_to() created a
  # table literally named `measurements`, backticks included -- which nothing
  # that quoted the name properly could then find.
  skip_if_not_installed("dplyr")
  con <- local_dolt()

  df <- data.frame(id = 1:4, grp = rep(c("a", "b"), each = 2), v = c(1, 2, 3, 4))
  dplyr::copy_to(con, df, "measurements", temporary = FALSE)

  expect_true("measurements" %in% DBI::dbListTables(con))
  expect_false(any(grepl("`", DBI::dbListTables(con), fixed = TRUE)))
  expect_equal(nrow(DBI::dbReadTable(con, "measurements")), 4L)

  out <- dplyr::compute(
    dplyr::summarise(
      dplyr::group_by(dplyr::tbl(con, "measurements"), grp),
      n = dplyr::n()
    ),
    name = "grp_counts", temporary = FALSE
  )

  expect_true("grp_counts" %in% DBI::dbListTables(con))
  expect_equal(sort(DBI::dbReadTable(con, "grp_counts")$n), c(2L, 2L))
})

test_that("already-quoted identifiers are unquoted whatever the style", {
  con <- local_dolt()
  DBI::dbExecute(con, 'CREATE TABLE "quoted me" (x INT)')

  # Double quotes are what this package emits; backticks are what dbplyr's
  # SQLite dialect emits; brackets round out the SQLite-accepted set.
  for (q in c('"quoted me"', "`quoted me`", "[quoted me]")) {
    expect_true(DBI::dbExistsTable(con, DBI::SQL(q)), info = q)
    expect_equal(DBI::dbListFields(con, DBI::SQL(q)), "x", info = q)
  }
})
