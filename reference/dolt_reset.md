# Undo uncommitted work

Undo uncommitted work

## Usage

``` r
dolt_reset(con, mode = c("soft", "hard"))
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- mode:

  \`"soft"\` unstages everything but keeps the working changes;
  \`"hard"\` discards uncommitted changes outright.

## Value

Invisibly \`TRUE\`.
