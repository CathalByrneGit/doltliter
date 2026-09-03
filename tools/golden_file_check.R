#!/usr/bin/env Rscript
# Golden-file check: run the same version-control operations through the
# doltlite CLI and through doltliter, and compare.
#
# This is a drift detector, not a unit test. The R package and the CLI link
# the same engine, so any disagreement means the binding has drifted -- a
# result column renamed upstream, an argument order changed, a return value
# that is now a hash where it used to be a status code. Those are exactly the
# breakages that a new DoltLite release introduces and that the package's own
# tests, which only ever talk to themselves, cannot see.
#
# Usage: Rscript tools/golden_file_check.R [path-to-doltlite]

library(doltliter)

args <- commandArgs(trailingOnly = TRUE)
cli <- if (length(args) >= 1L) args[[1L]] else Sys.which("doltlite")
if (!nzchar(cli) || !file.exists(cli)) {
  stop("the doltlite CLI was not found; pass its path as an argument",
       call. = FALSE)
}

message("CLI:      ", cli)
message("package:  doltliter ", as.character(utils::packageVersion("doltliter")))

main <- function(cli) {
  failures <- character()

  expect_same <- function(label, cli_value, pkg_value) {
    cli_value <- trimws(as.character(cli_value))
    pkg_value <- trimws(as.character(pkg_value))
    if (identical(cli_value, pkg_value)) {
      message(sprintf("  ok    %-28s %s", label,
                      paste(utils::head(pkg_value, 3), collapse = " | ")))
    } else {
      failures <<- c(failures, label)
      message(sprintf("  DRIFT %-28s", label))
      message("        cli: ", paste(cli_value, collapse = " | "))
      message("        pkg: ", paste(pkg_value, collapse = " | "))
    }
  }

  # Drive one database with the CLI and an identical one with the package, then
  # compare what each reports. Committer identity and messages are fixed so the
  # only thing that can differ is the binding.
  #
  # The whole build script goes through a single CLI process on purpose:
  # dolt_config() is per connection and is not persisted, so a statement per
  # invocation would leave every commit attributed to the default committer and
  # every commit hash different from the package's. Read-only queries
  # afterwards are unaffected and can each have their own process.
  run_cli <- function(db, sql) {
    out <- suppressWarnings(system2(cli, shQuote(db), input = sql,
                                    stdout = TRUE, stderr = TRUE))
    status <- attr(out, "status")
    if (!is.null(status) && status != 0L) {
      stop("CLI failed for: ", paste(sql, collapse = " "), "\n",
           paste(out, collapse = "\n"), call. = FALSE)
    }
    out
  }

  script <- c(
    "SELECT dolt_config('user.name', 'Golden File');",
    "SELECT dolt_config('user.email', 'golden@example.com');",
    "CREATE TABLE users (id INTEGER PRIMARY KEY, nm TEXT, active INTEGER);",
    "INSERT INTO users VALUES (1, 'ada', 1), (2, 'bob', 0);",
    "SELECT dolt_commit('-Am', 'initial load');",
    "SELECT dolt_branch('experiment');",
    "SELECT dolt_checkout('experiment');",
    "UPDATE users SET active = 1 WHERE id = 2;",
    "SELECT dolt_commit('-Am', 'activate bob');",
    "SELECT dolt_checkout('main');",
    "SELECT dolt_merge('experiment');"
  )

  cli_db <- tempfile("golden-cli", fileext = ".db")
  pkg_db <- tempfile("golden-pkg", fileext = ".db")
  on.exit(unlink(c(cli_db, pkg_db)), add = TRUE)

  message("\nbuilding the CLI database")
  run_cli(cli_db, script)

  message("building the doltliter database")
  con <- DBI::dbConnect(Doltlite(), pkg_db)
  on.exit(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con), add = TRUE)

  dolt_config(con, user.name = "Golden File", user.email = "golden@example.com")
  DBI::dbExecute(con, "CREATE TABLE users (id INTEGER PRIMARY KEY, nm TEXT, active INTEGER)")
  DBI::dbExecute(con, "INSERT INTO users VALUES (1, 'ada', 1), (2, 'bob', 0)")
  dolt_commit(con, "initial load")
  dolt_branch(con, "experiment")
  dolt_checkout(con, "experiment")
  DBI::dbExecute(con, "UPDATE users SET active = 1 WHERE id = 2")
  dolt_commit(con, "activate bob")
  dolt_checkout(con, "main")
  dolt_merge(con, "experiment")

  message("\ncomparing")

  # The content hashes are the sharpest check available: dolt_hashof_table()
  # and dolt_hashof_db() are history-independent, so two databases built the
  # same way agree on them exactly. If the package wrote anything different --
  # a value coerced differently, a column in another order -- these move.
  #
  # Commit hashes deliberately are not compared for equality: a commit covers
  # its timestamp, so two databases built moments apart legitimately differ.
  # Only the shape is checked.
  cli_commit <- trimws(run_cli(cli_db, "SELECT dolt_hashof('main');"))
  pkg_commit <- dolt_hashof(con, "main")
  expect_same("dolt_hashof(main) shape",
              grepl("^[0-9a-f]{40}$", cli_commit),
              grepl("^[0-9a-f]{40}$", pkg_commit))

  expect_same("dolt_hashof_table(users)",
              run_cli(cli_db, "SELECT dolt_hashof_table('users');"),
              dolt_hashof_table(con, "users"))

  expect_same("dolt_hashof_db()",
              run_cli(cli_db, "SELECT dolt_hashof_db();"),
              dolt_hashof_db(con))

  expect_same("dolt_log messages",
              run_cli(cli_db, "SELECT message FROM dolt_log;"),
              dolt_log(con)$message)

  expect_same("dolt_log committers",
              run_cli(cli_db, "SELECT committer FROM dolt_log;"),
              dolt_log(con)$committer)

  expect_same("dolt_branches names",
              run_cli(cli_db, "SELECT name FROM dolt_branches ORDER BY name;"),
              sort(dolt_branches(con)$name))

  expect_same("active_branch()",
              run_cli(cli_db, "SELECT active_branch();"),
              active_branch(con))

  expect_same("table contents",
              run_cli(cli_db, "SELECT id || ',' || nm || ',' || active FROM users ORDER BY id;"),
              with(DBI::dbReadTable(con, "users")[order(DBI::dbReadTable(con, "users")$id), ],
                   paste(id, nm, active, sep = ",")))

  expect_same("dolt_status (clean)",
              run_cli(cli_db, "SELECT count(*) FROM dolt_status;"),
              nrow(dolt_status(con)))

  # Column names are the other thing that drifts: a renamed column silently
  # turns a working wrapper into one that returns NULL.
  cli_cols <- run_cli(cli_db, "SELECT name FROM pragma_table_info('dolt_log');")
  expect_same("dolt_log column names", cli_cols, names(dolt_log(con)))

  cli_cols <- run_cli(cli_db, "SELECT name FROM pragma_table_info('dolt_status');")
  expect_same("dolt_status column names", cli_cols, names(dolt_status(con)))

  cli_cols <- run_cli(cli_db, "SELECT name FROM pragma_table_info('dolt_branches');")
  expect_same("dolt_branches column names", cli_cols, names(dolt_branches(con)))

  expect_same("dolt_version()",
              run_cli(cli_db, "SELECT dolt_version();"),
              dolt_version(con))

  if (length(failures)) {
    stop("\ngolden-file check found ", length(failures), " difference(s): ",
         paste(failures, collapse = ", "),
         "\nThe binding has drifted from the CLI. Check DoltLite's release notes.",
         call. = FALSE)
  }

  message("\ngolden-file check passed: the package and the CLI agree")

}

main(cli)
