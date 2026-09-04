# Write a data frame to a table

Behaves as it does for any DBI backend. Two DoltLite-specific points are
worth knowing:

## Usage

``` r
# S4 method for class 'DoltliteConnection,character,data.frame'
dbWriteTable(
  conn,
  name,
  value,
  ...,
  row.names = FALSE,
  overwrite = FALSE,
  append = FALSE,
  field.types = NULL,
  temporary = FALSE
)

# S4 method for class 'DoltliteConnection,character'
dbCreateTable(
  conn,
  name,
  fields,
  ...,
  field.types = NULL,
  row.names = NULL,
  temporary = FALSE
)

# S4 method for class 'DoltliteConnection,character,data.frame'
dbAppendTable(conn, name, value, ..., row.names = NULL)

# S4 method for class 'DoltliteConnection,SQL,data.frame'
dbWriteTable(conn, name, value, ...)

# S4 method for class 'DoltliteConnection,SQL'
dbCreateTable(conn, name, fields, ..., row.names = NULL, temporary = FALSE)

# S4 method for class 'DoltliteConnection,SQL,data.frame'
dbAppendTable(conn, name, value, ..., row.names = NULL)
```

## Arguments

- conn:

  a \`DoltliteConnection\`.

- name:

  the table name.

- value:

  a data frame.

- ...:

  unused.

- row.names:

  how to treat row names; see \[DBI::sqlRownamesToColumn()\].

- overwrite:

  whether to drop an existing table first.

- append:

  whether to append to an existing table.

- field.types:

  a named character vector of column types.

- temporary:

  whether to create a \`TEMPORARY\` table.

- fields:

  a data frame or named character vector defining the columns.

## Details

\* The default \`CREATE TABLE\` declares no primary key, so the table
keeps an ordinary \`rowid\` and behaves exactly as it would under
SQLite. \* If you use \`field.types\` to declare a \*\*non-\`INTEGER\`
primary key\*\*, the table becomes clustered on that key. It then has no
\`rowid\` column at all (as with SQLite's \`WITHOUT ROWID\`), and the
key columns are \`NOT NULL\`. Writing \`NULL\` into them fails. An
\`INTEGER PRIMARY KEY\` is unaffected – it stays a writable \`rowid\`
alias.

Writing a table changes the working set only. Call \[dolt_commit()\] to
record it in the version history.
