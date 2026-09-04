# Version-controlled data with doltliter

This vignette walks through a full cycle: connect, write a table,
commit, branch, modify, diff, merge, and resolve a conflict.

``` r

library(doltliter)
```

## Connecting

A DoltLite database is a single file.

``` r

path <- tempfile(fileext = ".db")
con <- DBI::dbConnect(Doltlite(), path)
con
#> <DoltliteConnection>
#>   Database: /tmp/RtmpbzhvlL/file205f77bccb5a.db
#>   Branch:   main
```

One caveat worth stating up front: pass a real path, not `""`. SQLite’s
anonymous temporary database is created in the *original* B-tree format,
and version control is not available there.

Commits are attributed per connection, and the setting is not persisted,
so configure it after connecting:

``` r

dolt_config(con, user.name = "Ada Lovelace", user.email = "ada@example.com")
```

## Writing data

Nothing surprising: this is ordinary DBI.

``` r

users <- data.frame(
  id     = 1:3,
  name   = c("ada", "bob", "cleo"),
  active = c(1L, 0L, 1L),
  stringsAsFactors = FALSE
)

DBI::dbWriteTable(con, "users", users,
                  field.types = c(id = "INTEGER PRIMARY KEY"))
DBI::dbReadTable(con, "users")
#>   id name active
#> 1  1  ada      1
#> 2  2  bob      0
#> 3  3 cleo      1
```

The primary key is declared here because
[`dolt_blame()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_blame.md)
later needs one: row attribution has to have a stable row identity to
attribute to. An `INTEGER PRIMARY KEY` stays an ordinary writable
`rowid` alias, exactly as in SQLite. A *non*-`INTEGER` primary key is
different — it makes the table clustered, with no `rowid` at all and
`NOT NULL` key columns.

The data is in the database, but nothing is in the history yet:

``` r

dolt_status(con)
#>   table_name staged    status
#> 1      users      0 new table
```

## The two kinds of commit

This is the distinction to hold on to.

[`DBI::dbBegin()`](https://dbi.r-dbi.org/reference/transactions.html) /
[`DBI::dbCommit()`](https://dbi.r-dbi.org/reference/transactions.html)
delimit a **SQL transaction**: the statements between them either all
apply or none do. That is about atomicity.

[`dolt_commit()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_commit.md)
writes a **commit into the version history**, the way `git commit` does.
That is about being able to come back later.

`dbCommit()` is “save the file”;
[`dolt_commit()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_commit.md)
is “commit to the repository”. Writing a table and committing the SQL
transaction leaves the rows in
[`dolt_status()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_status.md)
until you make a Dolt commit:

``` r

dolt_commit(con, "Initial load")
dolt_status(con)
#> [1] table_name staged     status    
#> <0 rows> (or 0-length row.names)
dolt_log(con)[, c("committer", "message")]
#>      committer                    message
#> 1 Ada Lovelace               Initial load
#> 2     doltlite Initialize data repository
```

A fresh database already contains one commit — DoltLite’s own
`Initialize data repository`.

## Branching

Each connection has its own active branch.

``` r

dolt_branch(con, "experiment")
dolt_checkout(con, "experiment")
active_branch(con)
#> [1] "experiment"
```

Make a change on the branch and commit it:

``` r

DBI::dbExecute(con, "UPDATE users SET active = 1 WHERE id = 2")
#> [1] 1
dolt_commit(con, "Activate bob")
```

`main` is untouched:

``` r

dolt_checkout(con, "main")
DBI::dbGetQuery(con, "SELECT id, name, active FROM users ORDER BY id")
#>   id name active
#> 1  1  ada      1
#> 2  2  bob      0
#> 3  3 cleo      1
```

You can also connect straight onto a branch. `doltliter` translates this
to DoltLite’s `dbname@branch` path syntax internally, and errors if the
branch does not exist rather than silently opening `main`:

``` r

con2 <- DBI::dbConnect(Doltlite(), path, branch = "experiment")
active_branch(con2)
#> [1] "experiment"
DBI::dbDisconnect(con2)
```

## Diffing

[`dolt_table_diff()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_table_diff.md)
compares a table between two refs, with `from_`/`to_` column pairs:

``` r

d <- dolt_table_diff(con, "users", from = "main", to = "experiment")
d[, c("diff_type", "to_id", "from_active", "to_active")]
#>   diff_type to_id from_active to_active
#> 1  modified     2           0         1
```

[`dolt_diff()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_diff.md)
works at the level of *which tables* changed in each commit. The
pseudo-commit `WORKING` covers uncommitted changes:

``` r

DBI::dbExecute(con, "UPDATE users SET name = 'ADA' WHERE id = 1")
#> [1] 1
dolt_diff(con, "users")[, c("commit_hash", "table_name", "data_change")]
#>                                commit_hash table_name data_change
#> 1                                  WORKING      users           1
#> 2 20791c47f213e1d5eddabdc66e27454a422604b5      users           1
dolt_reset(con, "hard")
```

For summaries rather than rows, there are
[`dolt_diff_stat()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_diff_stat.md),
[`dolt_diff_summary()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_diff_stat.md)
and
[`dolt_schema_diff()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_diff_stat.md);
for an executable rebuild,
[`dolt_patch()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_patch.md).

## Merging

A clean merge just works:

``` r

dolt_merge(con, "experiment")
#> [1] "73d9fdf5585b918cc1889258145424534a8ca425"
DBI::dbGetQuery(con, "SELECT id, name, active FROM users ORDER BY id")
#>   id name active
#> 1  1  ada      1
#> 2  2  bob      1
#> 3  3 cleo      1
```

## Resolving a conflict

Conflicts in DoltLite are **never durable**: they exist only inside the
transaction that produced them, and a commit is refused while any
remain. An autocommit merge that conflicts is therefore rolled back
whole — so to inspect and resolve conflicts, run the merge inside a
transaction.

Set up two branches that edit the same row:

``` r

dolt_checkout(con, "theirs", create = TRUE)
DBI::dbExecute(con, "UPDATE users SET name = 'THEIRS' WHERE id = 1")
#> [1] 1
dolt_commit(con, "Rename on theirs")

dolt_checkout(con, "main")
DBI::dbExecute(con, "UPDATE users SET name = 'OURS' WHERE id = 1")
#> [1] 1
dolt_commit(con, "Rename on main")
```

Now merge inside a transaction:

``` r

DBI::dbBegin(con)
dolt_merge(con, "theirs")
#> [1] "Merge has 1 conflict(s). Resolve and then commit with dolt_commit."
dolt_conflicts(con)
#>   table num_conflicts
#> 1 users             1
```

Inspect the detail, then take one side (or edit the rows directly):

``` r

dolt_conflicts_resolve(con, "ours")
dolt_conflicts(con)
#> [1] table         num_conflicts
#> <0 rows> (or 0-length row.names)
dolt_commit(con, "Merge theirs, keeping ours")
DBI::dbGetQuery(con, "SELECT id, name FROM users WHERE id = 1")
#>   id name
#> 1  1 OURS
```

[`dolt_commit()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_commit.md)
also ends the SQL transaction, so there is nothing left to `dbCommit()`.

## History and blame

``` r

dolt_log(con)[, c("committer", "message")]
#>      committer                    message
#> 1 Ada Lovelace Merge theirs, keeping ours
#> 2 Ada Lovelace             Rename on main
#> 3 Ada Lovelace           Rename on theirs
#> 4 Ada Lovelace               Activate bob
#> 5 Ada Lovelace               Initial load
#> 6     doltlite Initialize data repository
```

[`dolt_history()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_history.md)
gives every version of every row, and
[`dolt_at()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_at.md)
reads a table as it was at a revision:

``` r

first <- rev(dolt_log(con)$commit_hash)[1]
dolt_at(con, "users", first)
#> [1] id     name   active
#> <0 rows> (or 0-length row.names)
```

[`dolt_blame()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_blame.md)
attributes each live row to the commit that last set it. It needs a
primary key — there is no stable row identity without one:

``` r

dolt_blame(con, "users")[, c("id", "committer", "message")]
#>   id    committer                    message
#> 1  1 Ada Lovelace Merge theirs, keeping ours
#> 2  2 Ada Lovelace               Activate bob
#> 3  3 Ada Lovelace               Initial load
```

## dplyr

[`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html) works
over the connection with no extra setup: DoltLite’s SQL dialect is
SQLite’s, and `doltliter` reuses dbplyr’s SQLite translation.

``` r

library(dplyr)
#> 
#> Attaching package: 'dplyr'
#> The following objects are masked from 'package:stats':
#> 
#>     filter, lag
#> The following objects are masked from 'package:base':
#> 
#>     intersect, setdiff, setequal, union
tbl(con, "users") |>
  filter(active == 1) |>
  select(id, name) |>
  collect()
#> # A tibble: 3 × 2
#>      id name 
#>   <int> <chr>
#> 1     1 OURS 
#> 2     2 bob  
#> 3     3 cleo
```

## Remotes

Databases can push, pull, fetch and clone between each other, over the
filesystem or HTTP:

``` r

origin <- tempfile(fileext = ".db")
file.copy(path, origin)
#> [1] TRUE

clone_path <- tempfile(fileext = ".db")
clone <- DBI::dbConnect(Doltlite(), clone_path)
dolt_clone(clone, paste0("file://", origin))
#> [1] 0

DBI::dbReadTable(clone, "users")
#>   id name active
#> 1  1 OURS      1
#> 2  2  bob      1
#> 3  3 cleo      1
dolt_remotes(clone)[, c("name", "url")]
#>     name                                        url
#> 1 origin file:///tmp/RtmpbzhvlL/file205f693ad414.db
DBI::dbDisconnect(clone)
```

## Concurrency

DoltLite allows one durable writer at a time. A second connection that
begins a write transaction gets `SQLITE_BUSY` until the first finishes,
and a transaction that tries to upgrade after a peer advanced the store
gets `SQLITE_BUSY_SNAPSHOT`. Both are retryable, and `dbConnect()` sets
a five-second busy timeout by default:

``` r

con <- DBI::dbConnect(Doltlite(), path, busy_timeout = 30000)
```

``` r

DBI::dbDisconnect(con)
```
