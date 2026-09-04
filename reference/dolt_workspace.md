# Row-level working and staged edits

Set the \`staged\` column with an ordinary \`UPDATE\` to stage or
unstage individual rows.

## Usage

``` r
dolt_workspace(con, table)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- table:

  the table name.

## Value

A data frame.
