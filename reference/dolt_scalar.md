# Call a Dolt scalar SQL function

Escape hatch for a version-control function this package does not wrap
yet. Arguments are bound as parameters, so they are always treated as
values.

## Usage

``` r
dolt_scalar(con, fn, ...)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- fn:

  the function name, e.g. \`"dolt_commit"\`.

- ...:

  arguments, passed through in order.

## Value

The function's single return value.

## Examples

``` r
con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
dolt_scalar(con, "dolt_config", "user.name", "Ada")
#> [1] 0
DBI::dbDisconnect(con)
```
