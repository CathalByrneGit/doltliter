# Commit the current working set

Records a new commit in the version history. This is the Dolt sense of
"commit" and has nothing to do with \[DBI::dbCommit()\], which ends a
SQL transaction; see \[doltliter-transactions\].

## Usage

``` r
dolt_commit(
  con,
  message,
  author = NULL,
  all = TRUE,
  allow_empty = FALSE,
  force = FALSE
)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- message:

  the commit message.

- author:

  optionally \`"Name \<email\>"\`, overriding \[dolt_config()\] for this
  commit only.

- all:

  stage every changed table first, like \`git commit -a\` (the default).

- allow_empty:

  create a commit even when nothing changed.

- force:

  commit despite outstanding constraint violations.

## Value

The new commit hash, invisibly.

## Examples

``` r
con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
dolt_config(con, user.name = "Ada", user.email = "ada@example.com")
DBI::dbWriteTable(con, "users", data.frame(id = 1:2, nm = c("a", "b")))
dolt_commit(con, "Initial load")
dolt_log(con)$message
#> [1] "Initial load"               "Initialize data repository"
DBI::dbDisconnect(con)
```
