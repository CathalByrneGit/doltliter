# Content-addressed hashes

Content-addressed hashes

## Usage

``` r
dolt_hashof(con, ref = "HEAD")

dolt_hashof_table(con, table, ref = NULL)

dolt_hashof_db(con, ref = NULL)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- ref:

  a branch, tag, commit hash, \`HEAD\`, \`HEAD~N\` or \`HEAD^N\`.

- table:

  a table name.

## Value

A 40-character lowercase hex hash.
