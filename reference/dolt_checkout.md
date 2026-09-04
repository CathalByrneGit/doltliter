# Switch branches

Each connection tracks its own active branch. Uncommitted work belongs
to the \*branch\*, not the connection, so another connection that checks
out the same branch sees the same working set. There is no stash:
checking out does not shelve uncommitted changes.

## Usage

``` r
dolt_checkout(con, name, create = FALSE)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- name:

  the branch to check out.

- create:

  create the branch first (\`dolt_checkout('-b', name)\`).

## Value

Invisibly \`TRUE\`.
