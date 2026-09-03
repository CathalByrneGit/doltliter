# A fresh file-backed database per test.
#
# Deliberately not dbname = "": SQLite's anonymous temporary database is
# created in the original B-tree format, so doltlite_engine() is "orig" there
# and none of the version-control functions exist. Every version-control test
# would fail for a reason that has nothing to do with the code under test.
local_dolt <- function(branch = NULL, env = parent.frame(), configure = TRUE) {
  path <- tempfile("doltliter-test", fileext = ".db")
  con <- DBI::dbConnect(doltliter::Doltlite(), path, branch = branch)
  # withr::defer evaluates the expression in this frame when `env` exits, so
  # `con` and `path` are in scope.
  withr::defer(
    {
      if (DBI::dbIsValid(con)) suppressWarnings(DBI::dbDisconnect(con))
      unlink(path)
    },
    envir = env
  )
  if (configure) {
    dolt_config(con, user.name = "Test User", user.email = "test@example.com")
  }
  con
}

# Seed a committed table so branch/diff/merge tests have history to work with.
seed_users <- function(con, commit_message = "initial load") {
  DBI::dbExecute(con, "CREATE TABLE users (id INTEGER PRIMARY KEY, nm TEXT, active INTEGER)")
  DBI::dbExecute(con, "INSERT INTO users VALUES (1, 'ada', 1), (2, 'bob', 0)")
  dolt_commit(con, commit_message)
}

skip_if_not_prolly <- function(con) {
  engine <- DBI::dbGetQuery(con, "SELECT doltlite_engine() AS e")$e[[1]]
  testthat::skip_if_not(identical(engine, "prolly"),
                        "not a DoltLite-format database")
}
