# Cherry-pick a commit

Applies one commit's changes onto the current branch. Ranges are not
supported by DoltLite.

## Usage

``` r
dolt_cherry_pick(con, ref)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- ref:

  the commit to apply.

## Value

The new commit hash, or a message reporting conflicts.
