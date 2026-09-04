# Connect to a DoltLite database

Connect to a DoltLite database

## Usage

``` r
# S4 method for class 'DoltliteDriver'
dbConnect(
  drv,
  dbname = ":memory:",
  branch = NULL,
  flags = DOLTLITE_RWC,
  vfs = NULL,
  bigint = c("integer64", "integer", "numeric", "character"),
  busy_timeout = 5000L,
  ...
)
```

## Arguments

- drv:

  a \[Doltlite()\] driver.

- dbname:

  path to the database file. \`":memory:"\` opens a private in-memory
  database. An empty string opens an anonymous temporary database, which
  SQLite – and therefore DoltLite – creates in its \*original\* B-tree
  format, so version control is \*\*not\*\* available there; use
  \[tempfile()\] instead if you need it.

- branch:

  branch to check out on connect. Translated to DoltLite's
  \`dbname@branch\` path syntax internally. The branch must already
  exist; opening a database that does not have it is an error rather
  than a silent fall back to \`main\`.

- flags:

  one of \`DOLTLITE_RWC\` (read/write/create, the default),
  \`DOLTLITE_RW\` or \`DOLTLITE_RO\`.

- vfs:

  an optional SQLite VFS name.

- bigint:

  how to return 64-bit integers that do not fit in an R integer:
  \`"integer64"\` (default), \`"integer"\`, \`"numeric"\` or
  \`"character"\`.

- busy_timeout:

  milliseconds to wait for the DoltLite graph lock before giving up with
  \`SQLITE_BUSY\`. DoltLite permits one durable writer at a time, so a
  non-zero value is usually what you want.

- ...:

  unused.

## Value

A \`DoltliteConnection\`.
