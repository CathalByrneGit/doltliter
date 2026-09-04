# Working-set status

Working-set status

## Usage

``` r
dolt_status(con)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

## Value

A data frame with columns \`table_name\`, \`staged\` and \`status\`.
Zero rows means the working set is clean.
