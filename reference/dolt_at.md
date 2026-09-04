# A table as it existed at a given revision

A table as it existed at a given revision

## Usage

``` r
dolt_at(con, table, ref)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- table:

  the table name.

- ref:

  a commit hash, branch or tag.

## Value

A data frame with the table's own columns.
