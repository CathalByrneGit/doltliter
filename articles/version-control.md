# Branching, merging and conflicts

[`vignette("doltliter")`](https://cathalbyrnegit.github.io/doltliter/articles/doltliter.md)
covers a single pass through the commit loop. This article is about
working on more than one line of history at once: branching, merging,
what happens when two branches disagree, and how to undo things.

``` r

library(doltliter)

path <- tempfile(fileext = ".db")
con <- DBI::dbConnect(Doltlite(), path)
dolt_config(con, user.name = "Ada Lovelace", user.email = "ada@example.com")
```

We will curate a small reference table — the kind of data that gets
corrected over time, which is where version control earns its keep.

``` r

sites <- data.frame(
  id     = 1:4,
  name   = c("Ballycotton", "Roches Point", "Mizen Head", "Loop Head"),
  region = c("Cork", "Cork", "Cork", "Clare"),
  active = c(1L, 1L, 0L, 1L),
  stringsAsFactors = FALSE
)

DBI::dbWriteTable(con, "sites", sites,
                  field.types = c(id = "INTEGER PRIMARY KEY"))
dolt_commit(con, "Initial site list")
```

## Branches are per connection

Each connection holds its own active branch. Creating one does not move
you onto it:

``` r

dolt_branch(con, "review")
dolt_branches(con)[, c("name", "dirty")]
#>     name dirty
#> 1   main     0
#> 2 review     0
active_branch(con)
#> [1] "main"
```

[`dolt_checkout()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_checkout.md)
switches; `create = TRUE` does both at once.

``` r

dolt_checkout(con, "review")
active_branch(con)
#> [1] "review"
```

Work done here does not touch `main`:

``` r

DBI::dbExecute(con, "UPDATE sites SET active = 1 WHERE name = 'Mizen Head'")
#> [1] 1
dolt_commit(con, "Reactivate Mizen Head")

dolt_checkout(con, "main")
DBI::dbGetQuery(con, "SELECT name, active FROM sites WHERE name = 'Mizen Head'")
#>         name active
#> 1 Mizen Head      0
```

One thing to be aware of: uncommitted work belongs to the *branch*, not
the connection. There is no stash — checking out does not shelve
changes, and another connection that checks out the same branch will see
the same working set.

## A clean merge

When the two sides touch different rows, the merge just happens and
returns the new commit hash:

``` r

dolt_merge(con, "review")
#> [1] "120f8597586361f3f070b9df2702548cdee60877"
DBI::dbGetQuery(con, "SELECT name, active FROM sites ORDER BY id")
#>           name active
#> 1  Ballycotton      1
#> 2 Roches Point      1
#> 3   Mizen Head      1
#> 4    Loop Head      1
```

## A conflicting merge

Now the interesting case. Two branches edit the *same* row:

``` r

dolt_checkout(con, "regional", create = TRUE)
DBI::dbExecute(con, "UPDATE sites SET region = 'County Cork' WHERE id = 1")
#> [1] 1
dolt_commit(con, "Use full county names")

dolt_checkout(con, "main")
DBI::dbExecute(con, "UPDATE sites SET region = 'CORK' WHERE id = 1")
#> [1] 1
dolt_commit(con, "Normalise regions to upper case")
```

Here is the part that catches people out. Conflicts in DoltLite are
**never durable** — they exist only inside the transaction that produced
them. A merge run in autocommit mode, which is what you get by default,
is rolled back in full the moment it conflicts:

``` r

dolt_merge(con, "regional")
#> Error in `dbBind()`:
#> ! cannot merge: conflicts detected, autocommit transaction rolled back. Run the merge inside BEGIN/COMMIT to inspect dolt_conflicts and dolt_schema_conflicts, resolve with dolt_conflicts_resolve(), then commit with dolt_commit(). Conflicts are never committed as conflicts
```

Nothing was left behind to inspect:

``` r

nrow(dolt_conflicts(con))
#> [1] 0
DBI::dbGetQuery(con, "SELECT region FROM sites WHERE id = 1")
#>   region
#> 1   CORK
```

To actually work on the conflict, put the merge in a transaction:

``` r

DBI::dbBegin(con)
dolt_merge(con, "regional")
#> [1] "Merge has 1 conflict(s). Resolve and then commit with dolt_commit."
dolt_conflicts(con)
#>   table num_conflicts
#> 1 sites             1
```

The per-table view carries `base_`, `our_` and `their_` columns, so you
can see all three sides at once:

``` r

detail <- dolt_conflicts_table(con, "sites")
detail[, grep("region|dolt_conflict_id", names(detail), value = TRUE)]
#>   base_region our_region their_region dolt_conflict_id
#> 1        Cork       CORK  County Cork              1:0
```

Resolve by taking one side wholesale, or by editing the rows directly
and then resolving:

``` r

dolt_conflicts_resolve(con, "ours")
nrow(dolt_conflicts(con))
#> [1] 0

dolt_commit(con, "Merge regional, keeping upper-case regions")
DBI::dbGetQuery(con, "SELECT region FROM sites WHERE id = 1")
#>   region
#> 1   CORK
```

Note that
[`dolt_commit()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_commit.md)
also ended the SQL transaction, so there is nothing left for
[`DBI::dbCommit()`](https://dbi.r-dbi.org/reference/transactions.html)
to do:

``` r

DBI::dbCommit(con)
#> Error:
#> ! no transaction is open on this connection
```

A commit is refused while any conflict remains, so you cannot
accidentally record a half-merged state.

## Tags

Tags name a commit so you can come back to it:

``` r

dolt_tag(con, "v1.0")
dolt_tags(con)[, 1:2]
#>   tag_name                                 tag_hash
#> 1     v1.0 e8cb1b57b43375ffee36bd54b73beb31082f4792
```

They work anywhere a ref does — `dolt_at(con, "sites", "v1.0")`, or as a
diff endpoint.

## Undoing things

[`dolt_reset()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_reset.md)
throws away uncommitted work; `"soft"` unstages but keeps it, `"hard"`
discards it:

``` r

DBI::dbExecute(con, "DELETE FROM sites WHERE id = 4")
#> [1] 1
DBI::dbGetQuery(con, "SELECT count(*) AS n FROM sites")$n
#> [1] 3

dolt_reset(con, "hard")
DBI::dbGetQuery(con, "SELECT count(*) AS n FROM sites")$n
#> [1] 4
```

[`dolt_revert()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_revert.md)
is the one to reach for when the change is already committed. It does
not rewrite history — it writes a *new* commit applying the inverse:

``` r

DBI::dbExecute(con, "INSERT INTO sites VALUES (5, 'Blackrock', 'CORK', 1)")
#> [1] 1
oops <- dolt_commit(con, "Add Blackrock")

dolt_revert(con, oops)
#> [1] "97b54b14812e8469c330e9336206b66e8d78fbe3"
DBI::dbGetQuery(con, "SELECT count(*) AS n FROM sites")$n
#> [1] 4
dolt_log(con)$message[1:2]
#> [1] "Revert \"Add Blackrock\"" "Add Blackrock"
```

[`dolt_cherry_pick()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_cherry_pick.md)
applies a single commit from elsewhere onto the current branch, and
[`dolt_rebase()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_rebase.md)
replays a whole branch onto another. Both resolve conflicts the same way
[`dolt_merge()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_merge.md)
does, so the transaction advice above applies to them too.

``` r

DBI::dbDisconnect(con)
```
