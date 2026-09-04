# Which tables changed, per commit

Which tables changed, per commit

## Usage

``` r
dolt_diff(con, table = NULL)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- table:

  optionally restrict to one table.

## Value

A data frame with columns \`commit_hash\`, \`committer\`, \`email\`,
\`date\`, \`message\`, \`data_change\`, \`schema_change\` and
\`table_name\`. The pseudo-commit \`WORKING\` covers uncommitted
changes.
