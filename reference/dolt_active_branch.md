# The current branch

The current branch

## Usage

``` r
dolt_active_branch(con)

active_branch(con)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

## Value

The branch name, or \`NA\` when the connection is on a detached revision
(opened at a tag, commit hash or ancestor spec), which is read-only.

## Examples

``` r
con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
dolt_active_branch(con)
#> [1] "main"
DBI::dbDisconnect(con)
```
