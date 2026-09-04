# Conflicts

\`dolt_conflicts()\` summarises conflicted tables.
\`dolt_conflicts_table()\` returns the per-row detail, with
\`base\_\`/\`our\_\`/\`their\_\` columns and a \`dolt_conflict_id\`.
\`dolt_conflicts_resolve()\` takes one side wholesale.

## Usage

``` r
dolt_conflicts(con)

dolt_conflicts_table(con, table)

dolt_conflicts_resolve(con, side = c("ours", "theirs"), tables = NULL)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- table:

  a table name.

- side:

  \`"ours"\` or \`"theirs"\`.

- tables:

  tables to resolve; omit to resolve every conflicted table.

## Value

A data frame, or invisibly \`TRUE\` for the resolver.
