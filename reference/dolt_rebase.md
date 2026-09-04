# Rebase the current branch onto another

Atomic: a conflict or error restores the pre-rebase branch.

## Usage

``` r
dolt_rebase(
  con,
  upstream = NULL,
  interactive = FALSE,
  continue = FALSE,
  abort = FALSE
)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- upstream:

  the branch to replay onto.

- interactive:

  start an interactive rebase, which populates the \`dolt_rebase\` plan
  table for editing with ordinary SQL.

- continue, abort:

  finish or abandon an interactive rebase.

## Value

The result string.
