# Clone a remote database

Called on an already-open connection: DoltLite clones into the
connection's own database.

## Usage

``` r
dolt_clone(con, url, lazy = FALSE)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- url:

  the source URL.

- lazy:

  install refs and record \`origin\` without copying the reachable chunk
  graph, fetching chunks on demand instead. To reopen a lazy clone in
  another process, pass \`dbname\` as
  \`"file:/path/to/db?lazy_origin=1"\` with \`flags\` including SQLite's
  URI bit.

## Value

The result string.
