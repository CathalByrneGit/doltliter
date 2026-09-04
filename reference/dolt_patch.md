# Executable patch between two refs

Executable patch between two refs

## Usage

``` r
dolt_patch(con, from, to = NULL, table = NULL)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- from, to:

  endpoint refs. \`from\` may instead be a range string such as
  \`"v1.0..v2.0"\`, in which case leave \`to\` empty.

- table:

  optionally restrict to one table.

## Value

A data frame of ordered SQLite statements, with \`statement_order\` and
\`diff_type\` columns.
