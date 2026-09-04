# Time travel: history, diffs and blame

Committing data is only half the point. The other half is being able to
ask what the data used to be, what changed between two moments, and who
changed it.

``` r

library(doltliter)

con <- DBI::dbConnect(Doltlite(), tempfile(fileext = ".db"))
dolt_config(con, user.name = "Ada Lovelace", user.email = "ada@example.com")
```

Let’s build a table with a few revisions behind it. The primary key
matters here:
[`dolt_blame()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_blame.md)
needs one, because without a stable row identity there is nothing to
attribute a change *to*.

``` r

DBI::dbWriteTable(
  con, "readings",
  data.frame(id = 1:3,
             sensor = c("A", "B", "C"),
             value  = c(10.0, 20.0, 30.0)),
  field.types = c(id = "INTEGER PRIMARY KEY")
)
dolt_commit(con, "First calibration run")

DBI::dbExecute(con, "UPDATE readings SET value = 21.5 WHERE id = 2")
#> [1] 1
dolt_commit(con, "Recalibrate sensor B")

DBI::dbExecute(con, "INSERT INTO readings VALUES (4, 'D', 40.0)")
#> [1] 1
dolt_commit(con, "Add sensor D")
```

## What happened, and when

``` r

dolt_log(con)[, c("committer", "date", "message")]
#>      committer                date                    message
#> 1 Ada Lovelace 2026-09-04 21:01:10               Add sensor D
#> 2 Ada Lovelace 2026-09-04 21:01:10       Recalibrate sensor B
#> 3 Ada Lovelace 2026-09-04 21:01:10      First calibration run
#> 4     doltlite 2026-09-04 21:01:10 Initialize data repository
```

[`dolt_diff()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_diff.md)
works one level up — which *tables* changed in each commit, rather than
which rows:

``` r

dolt_diff(con, "readings")[, c("commit_hash", "data_change", "schema_change")]
#>                                commit_hash data_change schema_change
#> 1 ffb6319119086a5873e0013259ece663888ef0b4           1             0
#> 2 f439b798211b27e5cbef1585cefdbc4d2df0d233           1             0
#> 3 b0ae9e1306452069285ab338e5892dcd672e217f           1             1
```

Uncommitted work shows up under the pseudo-commit `WORKING`, which is a
convenient way to see whether anything is pending:

``` r

DBI::dbExecute(con, "UPDATE readings SET value = 41.0 WHERE id = 4")
#> [1] 1
dolt_diff(con, "readings")$commit_hash[1]
#> [1] "WORKING"
dolt_status(con)
#>   table_name staged   status
#> 1   readings      0 modified
```

## Row-level diffs

[`dolt_table_diff()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_table_diff.md)
is the workhorse. Give it two endpoints and it returns one row per
changed row, with `from_` and `to_` columns side by side:

``` r

d <- dolt_table_diff(con, "readings", from = "HEAD", to = "WORKING")
d[, c("diff_type", "to_id", "from_value", "to_value")]
#>   diff_type to_id from_value to_value
#> 1  modified     4         40       41
```

Endpoints are anything DoltLite understands as a ref — a branch, a tag,
a commit hash, `HEAD~2`, `WORKING`:

``` r

dolt_table_diff(con, "readings", from = "HEAD~2", to = "HEAD")[
  , c("diff_type", "to_id", "from_value", "to_value")]
#>   diff_type to_id from_value to_value
#> 1  modified     2         20     21.5
#> 2     added     4         NA     40.0
```

A range string works too, which is handy when comparing branches. Two
dots are the two endpoints; three dots is merge-base to the right
endpoint:

``` r

dolt_table_diff(con, "readings", range = "main..feature")
dolt_table_diff(con, "readings", range = "main...feature")
```

For a summary rather than the rows themselves:

``` r

dolt_diff_stat(con, "HEAD~2", "HEAD")
#>   table_name rows_unmodified rows_added rows_deleted rows_modified cells_added
#> 1   readings               2          1            0             1           3
#>   cells_deleted cells_modified old_row_count new_row_count old_cell_count
#> 1             0              1             3             4              9
#>   new_cell_count
#> 1             12
```

``` r

dolt_reset(con, "hard")
```

## Reading the past directly

[`dolt_at()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_at.md)
reads a table as it was at some revision — no checkout, no branch
switching, just a query against a historical snapshot:

``` r

first <- rev(dolt_log(con)$commit_hash)[2]   # the first real commit

dolt_at(con, "readings", first)
#>   id sensor value
#> 1  1      A    10
#> 2  2      B    20
#> 3  3      C    30
DBI::dbReadTable(con, "readings")
#>   id sensor value
#> 1  1      A  10.0
#> 2  2      B  21.5
#> 3  3      C  30.0
#> 4  4      D  40.0
```

[`dolt_history()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_history.md)
goes wider: every version of every row across the commit ancestry, with
the commit metadata attached. It is the right tool for “plot this value
over time”:

``` r

h <- dolt_history(con, "readings")
h[h$id == 2, c("id", "sensor", "value", "commit_hash")]
#>   id sensor value                              commit_hash
#> 2  2      B  21.5 ffb6319119086a5873e0013259ece663888ef0b4
#> 6  2      B  21.5 f439b798211b27e5cbef1585cefdbc4d2df0d233
#> 9  2      B  20.0 b0ae9e1306452069285ab338e5892dcd672e217f
```

## Who changed this row

[`dolt_blame()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_blame.md)
attributes each *live* row to the commit that last set it:

``` r

dolt_blame(con, "readings")[, c("id", "committer", "message")]
#>   id    committer               message
#> 1  1 Ada Lovelace First calibration run
#> 2  2 Ada Lovelace  Recalibrate sensor B
#> 3  3 Ada Lovelace First calibration run
#> 4  4 Ada Lovelace          Add sensor D
```

It walks first parents from `HEAD`. Schema-only changes such as
`ALTER TABLE ... ADD COLUMN` do not update blame, so a column addition
will not make every row look freshly touched.

## Content hashes

Every table root and the catalog as a whole are content-addressed, and
the table and database hashes are *history-independent*: the same rows
hash the same regardless of how they got there.

``` r

dolt_hashof(con, "HEAD")        # commit hash — covers the timestamp too
#> [1] "ffb6319119086a5873e0013259ece663888ef0b4"
dolt_hashof_table(con, "readings")
#> [1] "6cf508013fc3b1e71c3686c3d24fcb1ab0a78d02"
dolt_hashof_db(con)
#> [1] "b39b752292634f8afaac792b6302126f1ae80874"
```

That makes
[`dolt_hashof_table()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_hashof.md)
a cheap way to ask “did this table actually change?” across two
databases or two points in time, without diffing.

## Generating a patch

[`dolt_patch()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_patch.md)
turns a diff into ordered, executable SQLite statements — useful for
review, or for replaying a change somewhere else:

``` r

p <- dolt_patch(con, "HEAD~1", "HEAD")
p[, c("statement_order", "diff_type", "statement")]
#>   statement_order diff_type
#> 1               1      data
#>                                                          statement
#> 1 INSERT INTO "readings"("id","sensor","value") VALUES (4,'D',40);
```

``` r

DBI::dbDisconnect(con)
```
