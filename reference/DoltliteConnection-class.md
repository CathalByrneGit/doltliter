# DoltLite connection class

DoltLite connection class

## Usage

``` r
# S4 method for class 'DoltliteConnection'
dbIsValid(dbObj, ...)

# S4 method for class 'DoltliteConnection'
dbDisconnect(conn, ...)

# S4 method for class 'DoltliteConnection'
show(object)

# S4 method for class 'DoltliteConnection'
dbGetInfo(dbObj, ...)

# S4 method for class 'DoltliteConnection,character'
dbSendQuery(conn, statement, params = NULL, ..., immediate = FALSE)

# S4 method for class 'DoltliteConnection,character'
dbSendStatement(conn, statement, params = NULL, ..., immediate = FALSE)

# S4 method for class 'DoltliteConnection,character'
dbGetQuery(conn, statement, params = NULL, ..., n = -1, immediate = FALSE)

# S4 method for class 'DoltliteConnection,character'
dbExecute(conn, statement, params = NULL, ..., immediate = FALSE)

# S4 method for class 'DoltliteConnection'
dbListTables(conn, ...)

# S4 method for class 'DoltliteConnection,character'
dbExistsTable(conn, name, ...)

# S4 method for class 'DoltliteConnection,character'
dbListFields(conn, name, ...)

# S4 method for class 'DoltliteConnection,character'
dbRemoveTable(conn, name, ..., temporary = FALSE, fail_if_missing = TRUE)

# S4 method for class 'DoltliteConnection,character'
dbReadTable(conn, name, ..., row.names = FALSE, check.names = TRUE)

# S4 method for class 'DoltliteConnection,character'
dbQuoteIdentifier(conn, x, ...)

# S4 method for class 'DoltliteConnection,SQL'
dbQuoteIdentifier(conn, x, ...)

# S4 method for class 'DoltliteConnection,character'
dbQuoteString(conn, x, ...)

# S4 method for class 'DoltliteConnection,SQL'
dbQuoteString(conn, x, ...)

# S4 method for class 'DoltliteConnection,SQL'
dbExistsTable(conn, name, ...)

# S4 method for class 'DoltliteConnection,SQL'
dbListFields(conn, name, ...)

# S4 method for class 'DoltliteConnection,SQL'
dbReadTable(conn, name, ...)

# S4 method for class 'DoltliteConnection,SQL'
dbRemoveTable(conn, name, ...)
```

## Arguments

- dbObj, drv, conn:

  a \`DoltliteConnection\`.

- ...:

  passed on to methods.

- statement:

  an SQL string.

- params:

  optional query parameters, as a list.

- immediate:

  whether to execute the statement immediately.

- name:

  a table name.

- x:

  a string or identifier to quote.

## Slots

- `ptr`:

  external pointer to the C connection object.

- `dbname`:

  the database path, without any branch suffix.

- `branch`:

  the branch requested at connect time, or \`NA\`.

- `bigint`:

  how out-of-range 64-bit integers are returned.

- `state`:

  an environment holding mutable per-connection state, chiefly whether a
  transaction is open. S4 slots are copy-on-modify, so mutable
  bookkeeping has to live in a reference object.
