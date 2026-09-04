# Exchange commits with a remote

Exchange commits with a remote

## Usage

``` r
dolt_push(con, remote = "origin", branch = NULL)

dolt_fetch(con, remote = "origin", branch = NULL)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- remote:

  the remote name, \`"origin"\` by default.

- branch:

  the branch to transfer. Omit for the remote's default behaviour.

## Value

The result string.
