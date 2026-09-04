# Manage remotes

Manage remotes

## Usage

``` r
dolt_remote(con, action = NULL, name = NULL, url = NULL)

dolt_remotes(con)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- action:

  \`"add"\` or \`"remove"\`. Omit to list remotes.

- name:

  the remote name, e.g. \`"origin"\`.

- url:

  a \`file://\` or \`http(s)://\` URL. The HTTP form includes the
  database name, e.g. \`http://host:8080/mydb.db\`.

## Value

A data frame when listing, otherwise invisibly \`TRUE\`.

## Examples

``` r
con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
dolt_remote(con)
#> [1] name        url         fetch_specs params     
#> <0 rows> (or 0-length row.names)
DBI::dbDisconnect(con)
```
