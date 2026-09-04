# Diff statistics and summaries

Diff statistics and summaries

## Usage

``` r
dolt_diff_stat(con, from, to, table = NULL)

dolt_diff_summary(con, from, to, table = NULL)

dolt_schema_diff(con, from, to, table = NULL)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- from, to:

  endpoint refs.

- table:

  optionally restrict to one table.

## Value

A data frame. \`dolt_diff_stat()\` gives row and cell counts,
\`dolt_diff_summary()\` gives per-table added / dropped / renamed /
modified, and \`dolt_schema_diff()\` gives schema-level changes.
