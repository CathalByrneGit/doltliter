# Query a Dolt virtual table or table-valued function

Escape hatch for a version-control relation this package does not wrap
yet.

## Usage

``` r
dolt_table(con, fn, ...)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- fn:

  the relation name, e.g. \`"dolt_log"\` or \`"dolt_diff_users"\`.

- ...:

  arguments. With none, the relation is read as a plain virtual table;
  with arguments, as a table-valued function.

## Value

A data frame.
