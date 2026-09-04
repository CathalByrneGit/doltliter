# Row-level differences for one table

Wraps DoltLite's per-table \`dolt_diff\_\<table\>\` relation. Columns
come in \`from\_\`/\`to\_\` pairs plus commit metadata and a
\`diff_type\`.

## Usage

``` r
dolt_table_diff(con, table, from = NULL, to = NULL, range = NULL)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- table:

  the table name.

- from, to:

  endpoints: a branch, tag, commit hash, \`HEAD~1\`, \`WORKING\`, and so
  on. Give both for a two-point diff. Give neither to get the table's
  whole per-commit row history.

- range:

  alternatively a range string: \`"main..feature"\` for the two
  endpoints, or \`"main...feature"\` for merge-base to right endpoint.

## Value

A data frame.

## Examples

``` r
con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
dolt_config(con, user.name = "Ada", user.email = "ada@example.com")
DBI::dbWriteTable(con, "t", data.frame(id = 1:2, v = c(10, 20)))
dolt_commit(con, "init")
DBI::dbExecute(con, "UPDATE t SET v = 99 WHERE id = 1")
#> [1] 1
dolt_table_diff(con, "t", from = "HEAD", to = "WORKING")$diff_type
#> [1] "modified"
DBI::dbDisconnect(con)
```
