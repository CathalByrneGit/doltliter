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
