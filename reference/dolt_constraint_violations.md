# Constraint violations left by a merge

Merges apply cell by cell and do not run referential actions inline, so
violating rows land here afterwards. A commit is refused while any
remain unless \`force = TRUE\`.

## Usage

``` r
dolt_constraint_violations(con, table = NULL)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- table:

  optionally a table name, for the per-table detail.

## Value

A data frame.
