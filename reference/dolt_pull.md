# Fetch, then fast-forward or merge

Fast-forwards when the local branch is an ancestor of the remote tip,
and three-way merges when it has diverged. A non-current branch that is
not a fast-forward is refused.

## Usage

``` r
dolt_pull(con, remote = "origin", branch = NULL)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- remote:

  the remote name.

- branch:

  the branch to pull.

## Value

The result string.
