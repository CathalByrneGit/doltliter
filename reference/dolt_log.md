# Commit history

Commit history

## Usage

``` r
dolt_log(con, ref = NULL)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- ref:

  optionally a branch, tag or revision range, e.g. \`"feature"\`,
  \`"main..feature"\`. Omit for the current branch's history.

## Value

A data frame with columns \`commit_hash\`, \`committer\`, \`email\`,
\`date\` and \`message\`, newest first.

## Examples

``` r
con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
dolt_config(con, user.name = "Ada", user.email = "ada@example.com")
DBI::dbWriteTable(con, "t", data.frame(x = 1))
dolt_commit(con, "init")
dolt_log(con)[, c("committer", "message")]
#>   committer                    message
#> 1       Ada                       init
#> 2  doltlite Initialize data repository
DBI::dbDisconnect(con)
```
