# Transactions

These are ordinary SQLite transactions, and they are \*\*not\*\* Dolt
commits.

## Usage

``` r
# S4 method for class 'DoltliteConnection'
dbBegin(conn, ...)

# S4 method for class 'DoltliteConnection'
dbCommit(conn, ...)

# S4 method for class 'DoltliteConnection'
dbRollback(conn, ...)
```

## Arguments

- conn:

  a \`DoltliteConnection\`.

- ...:

  unused.

## Details

\`dbBegin()\` / \`dbCommit()\` / \`dbRollback()\` group statements so
that they either all take effect or none do. That is a property of the
\*working set\*: after \`dbCommit()\` the rows are in the database, but
they are still uncommitted from Dolt's point of view and will show up in
\[dolt_status()\].

\[dolt_commit()\] is the other kind of commit: it writes a new,
content-addressed commit into the version history, the way \`git
commit\` does. Nothing is recorded in the history until you call it.

A useful mental model: \`dbCommit()\` is "save the file",
\`dolt_commit()\` is "commit to the repository".

One asymmetry is worth remembering: \[dolt_commit()\] \*\*ends the
enclosing SQL transaction\*\* as a side effect. After calling it inside
a \`dbBegin()\`/\`dbCommit()\` block there is no transaction left to
commit, and a further \`dbCommit()\` will report that none is active.
This backend asks SQLite whether a transaction is open rather than
tracking it separately, so \[DBI::dbBegin()\] and friends stay accurate
either way.

Note that DoltLite permits one durable writer at a time. A second
connection that begins a write transaction gets \`SQLITE_BUSY\` until
the first finishes; see the \`busy_timeout\` argument to
\[DBI::dbConnect()\].
