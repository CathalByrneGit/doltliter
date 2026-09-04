# Revert a commit

Creates a new commit applying the inverse of \`ref\`. The initial commit
cannot be reverted.

## Usage

``` r
dolt_revert(con, ref)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- ref:

  a commit hash or ref to revert.

## Value

The result string: a new commit hash, or a message reporting conflicts.
