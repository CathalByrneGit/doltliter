# doltliter

📖 **Documentation: <https://cathalbyrnegit.github.io/doltliter/>**

A [DBI](https://dbi.r-dbi.org) backend for
[DoltLite](https://github.com/dolthub/doltlite) — a fork of SQLite whose
storage engine is a content-addressed prolly tree, giving you Git-style
version control over a SQL database.

Ordinary DBI works exactly as it does for any SQLite database. On top of
that you get commits, branches, diffs, merges, tags and remotes, as
plain R functions.

``` r

library(doltliter)

con <- DBI::dbConnect(doltliter::Doltlite(), "mydata.db")
dolt_config(con, user.name = "Ada Lovelace", user.email = "ada@example.com")

DBI::dbWriteTable(con, "users", users_df)
dolt_commit(con, "Initial load")

dolt_branch(con, "experiment")
dolt_checkout(con, "experiment")
DBI::dbExecute(con, "UPDATE users SET active = 1 WHERE id = 2")
dolt_commit(con, "Activate Bob")

dolt_table_diff(con, "users", from = "main", to = "experiment")
#>   diff_type to_id from_active to_active
#> 1  modified     2           0         1

dolt_checkout(con, "main")
dolt_merge(con, "experiment")

library(dplyr)
tbl(con, "users") |> filter(active == 1) |> collect()
```

## Installation

``` r

# install.packages("remotes")
remotes::install_github("CathalByrneGit/doltliter")
```

The package compiles against a `libdoltlite`, and `configure` finds one
for you: an already-installed DoltLite if you have one, otherwise a
vendored amalgamation or a prebuilt release library. It then runs a
probe asserting the engine really is `prolly`, so a build that
accidentally linked stock SQLite fails at install time rather than at
the first `dolt_*` call.

Pick a strategy with `DOLTLITER_STRATEGY=system|vendor|download` and pin
the engine with `DOLTLITE_VERSION`. Full details, and what to do when a
build fails, are in [Installation and linking
strategies](https://cathalbyrnegit.github.io/doltliter/articles/installation.html).

## Two kinds of “commit”

The one thing worth internalising before you start.

|  | What it does | When it matters |
|----|----|----|
| [`DBI::dbCommit()`](https://dbi.r-dbi.org/reference/transactions.html) | Ends a **SQL transaction**. Statements since `dbBegin()` either all apply or none do. | Atomicity of a batch of writes. |
| [`dolt_commit()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_commit.md) | Writes a **commit into the version history**, like `git commit`. | Anything you want to diff, branch, or come back to. |

`dbCommit()` is “save the file”;
[`dolt_commit()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_commit.md)
is “commit to the repository”. Data that is written and `dbCommit()`-ed
is in the database but still uncommitted as far as Dolt is concerned —
it shows up in
[`dolt_status()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_status.md)
until you call
[`dolt_commit()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_commit.md).

## What you get

**Standard DBI** — `dbConnect`, `dbDisconnect`, `dbGetQuery`,
`dbSendQuery`, `dbSendStatement`, `dbBind`, `dbFetch`, `dbColumnInfo`,
`dbWriteTable`, `dbReadTable`, `dbAppendTable`, `dbCreateTable`,
`dbListTables`, `dbListFields`, `dbExistsTable`, `dbRemoveTable`,
`dbBegin`/`dbCommit`/ `dbRollback`, and the rest.
[`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html) and
lazy query translation work out of the box.

**Version control** —

| Area | Functions |
|----|----|
| Commit loop | [`dolt_config()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_config.md), [`dolt_add()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_add.md), [`dolt_commit()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_commit.md), [`dolt_status()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_status.md), [`dolt_reset()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_reset.md), [`dolt_revert()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_revert.md), [`dolt_cherry_pick()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_cherry_pick.md) |
| Branches | [`dolt_branch()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_branch.md), [`dolt_branches()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_branch.md), [`dolt_checkout()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_checkout.md), [`active_branch()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_active_branch.md), [`dolt_merge()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_merge.md), [`dolt_merge_base()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_merge_base.md), [`dolt_merge_status()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_merge_status.md), [`dolt_rebase()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_rebase.md), [`dolt_tag()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_tag.md), [`dolt_tags()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_tag.md) |
| History | [`dolt_log()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_log.md), [`dolt_diff()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_diff.md), [`dolt_table_diff()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_table_diff.md), [`dolt_diff_stat()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_diff_stat.md), [`dolt_diff_summary()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_diff_stat.md), [`dolt_schema_diff()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_diff_stat.md), [`dolt_patch()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_patch.md), [`dolt_history()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_history.md), [`dolt_at()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_at.md), [`dolt_blame()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_blame.md), [`dolt_workspace()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_workspace.md), [`dolt_schemas()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_schemas.md) |
| Conflicts | [`dolt_conflicts()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_conflicts.md), [`dolt_conflicts_table()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_conflicts.md), [`dolt_conflicts_resolve()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_conflicts.md), [`dolt_constraint_violations()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_constraint_violations.md) |
| Remotes | [`dolt_remote()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_remote.md), [`dolt_remotes()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_remote.md), [`dolt_push()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_push.md), [`dolt_pull()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_pull.md), [`dolt_fetch()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_push.md), [`dolt_clone()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_clone.md), [`dolt_creds()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_creds.md) |
| Introspection | [`dolt_hashof()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_hashof.md), [`dolt_hashof_table()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_hashof.md), [`dolt_hashof_db()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_hashof.md), [`dolt_version()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_version.md), [`dolt_gc()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_gc.md) |

Anything not wrapped is still reachable, safely, through
[`dolt_scalar()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_scalar.md)
(for `SELECT dolt_x(...)`) and
[`dolt_table()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_table.md)
(for `SELECT * FROM dolt_x(...)`).

All arguments are passed as **bound parameters**, never interpolated
into SQL, so a commit message containing quotes or semicolons is just a
message.

## Documentation

- [Version-controlled data with
  doltliter](https://cathalbyrnegit.github.io/doltliter/articles/doltliter.html)
  — start here.
- [Branching, merging and
  conflicts](https://cathalbyrnegit.github.io/doltliter/articles/version-control.html)
- [Time travel: history, diffs and
  blame](https://cathalbyrnegit.github.io/doltliter/articles/time-travel.html)
- [Using
  dplyr](https://cathalbyrnegit.github.io/doltliter/articles/dplyr.html)
- [Installation and linking
  strategies](https://cathalbyrnegit.github.io/doltliter/articles/installation.html)

Design notes: [DBI
conformance](https://cathalbyrnegit.github.io/doltliter/articles/dbi-compliance.html)
(the full `DBItest` suite runs in the test suite and passes, apart from
two naming conventions that follow from the package’s own name) and [Why
a native binding, and how it
links](https://cathalbyrnegit.github.io/doltliter/articles/feasibility-notes.html)
(release artifacts, platform coverage, and why a CRAN submission would
vendor the amalgamation).

## License

MIT. DoltLite itself is distributed under its own terms; a package built
from the vendored amalgamation includes DoltLite and is subject to those
too.
