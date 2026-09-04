# Every version of every row in a table

Every version of every row in a table

## Usage

``` r
dolt_history(con, table, ref = NULL)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- table:

  the table name.

- ref:

  optionally start the walk from another branch, tag or commit.

## Value

A data frame: the table's columns plus commit metadata.
