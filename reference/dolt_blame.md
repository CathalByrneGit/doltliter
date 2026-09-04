# Which commit last set each row

A first-parent walk from \`HEAD\`. Schema-only changes such as \`ALTER
TABLE ADD COLUMN\` do not update blame.

## Usage

``` r
dolt_blame(con, table)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- table:

  the table name.

## Value

A data frame with the primary key plus \`commit\`, \`commit_date\`,
\`committer\`, \`email\` and \`message\`.
