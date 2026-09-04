# Merge status

Merge status

## Usage

``` r
dolt_merge_status(con)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

## Value

A one-row data frame. \`is_merging\` is \`0\` and the other columns are
\`NA\` when no merge is in progress.
