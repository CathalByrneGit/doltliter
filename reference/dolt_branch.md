# Create, list or delete branches

Create, list or delete branches

## Usage

``` r
dolt_branch(con, name = NULL, delete = FALSE, force = FALSE)

dolt_branches(con)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- name:

  the branch name. Omit to list branches instead.

- delete:

  delete \`name\` rather than creating it.

- force:

  overwrite an existing branch.

## Value

When listing, a data frame of branches. Otherwise invisibly \`TRUE\`.

## Examples

``` r
con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
dolt_config(con, user.name = "Ada", user.email = "ada@example.com")
DBI::dbWriteTable(con, "t", data.frame(x = 1))
dolt_commit(con, "init")
dolt_branch(con, "experiment")
dolt_branch(con)$name
#> [1] "main"       "experiment"
DBI::dbDisconnect(con)
```
