# doltliter

<!-- badges: start -->
[![R-CMD-check](https://github.com/CathalByrneGit/doltliter/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/CathalByrneGit/doltliter/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://github.com/CathalByrneGit/doltliter/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/CathalByrneGit/doltliter/actions/workflows/pkgdown.yaml)
<!-- badges: end -->

📖 **Documentation: <https://cathalbyrnegit.github.io/doltliter/>**

A [DBI](https://dbi.r-dbi.org) backend for
[DoltLite](https://github.com/dolthub/doltlite) — a fork of SQLite whose
storage engine is a content-addressed prolly tree, giving you Git-style
version control over a SQL database.

Ordinary DBI works exactly as it does for any SQLite database. On top of that
you get commits, branches, diffs, merges, tags and remotes, as plain R
functions.

```r
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

```r
# install.packages("remotes")
remotes::install_github("CathalByrneGit/doltliter")
```

The package compiles against a `libdoltlite`, and `configure` finds one for
you: an already-installed DoltLite if you have one, otherwise a vendored
amalgamation or a prebuilt release library. It then runs a probe asserting the
engine really is `prolly`, so a build that accidentally linked stock SQLite
fails at install time rather than at the first `dolt_*` call.

Pick a strategy with `DOLTLITER_STRATEGY=system|vendor|download` and pin the
engine with `DOLTLITE_VERSION`. Full details, and what to do when a build
fails, are in
[Installation and linking strategies](https://cathalbyrnegit.github.io/doltliter/articles/installation.html).

## Two kinds of "commit"

The one thing worth internalising before you start.

| | What it does | When it matters |
|---|---|---|
| `DBI::dbCommit()` | Ends a **SQL transaction**. Statements since `dbBegin()` either all apply or none do. | Atomicity of a batch of writes. |
| `dolt_commit()` | Writes a **commit into the version history**, like `git commit`. | Anything you want to diff, branch, or come back to. |

`dbCommit()` is "save the file"; `dolt_commit()` is "commit to the
repository". Data that is written and `dbCommit()`-ed is in the database but
still uncommitted as far as Dolt is concerned — it shows up in `dolt_status()`
until you call `dolt_commit()`.

## What you get

**Standard DBI** — `dbConnect`, `dbDisconnect`, `dbGetQuery`, `dbSendQuery`,
`dbSendStatement`, `dbBind`, `dbFetch`, `dbColumnInfo`, `dbWriteTable`,
`dbReadTable`, `dbAppendTable`, `dbCreateTable`, `dbListTables`,
`dbListFields`, `dbExistsTable`, `dbRemoveTable`, `dbBegin`/`dbCommit`/
`dbRollback`, and the rest. `dplyr::tbl()` and lazy query translation work out
of the box.

**Version control** —

| Area | Functions |
|---|---|
| Commit loop | `dolt_config()`, `dolt_add()`, `dolt_commit()`, `dolt_status()`, `dolt_reset()`, `dolt_revert()`, `dolt_cherry_pick()` |
| Branches | `dolt_branch()`, `dolt_branches()`, `dolt_checkout()`, `active_branch()`, `dolt_merge()`, `dolt_merge_base()`, `dolt_merge_status()`, `dolt_rebase()`, `dolt_tag()`, `dolt_tags()` |
| History | `dolt_log()`, `dolt_diff()`, `dolt_table_diff()`, `dolt_diff_stat()`, `dolt_diff_summary()`, `dolt_schema_diff()`, `dolt_patch()`, `dolt_history()`, `dolt_at()`, `dolt_blame()`, `dolt_workspace()`, `dolt_schemas()` |
| Conflicts | `dolt_conflicts()`, `dolt_conflicts_table()`, `dolt_conflicts_resolve()`, `dolt_constraint_violations()` |
| Remotes | `dolt_remote()`, `dolt_remotes()`, `dolt_push()`, `dolt_pull()`, `dolt_fetch()`, `dolt_clone()`, `dolt_creds()` |
| Introspection | `dolt_hashof()`, `dolt_hashof_table()`, `dolt_hashof_db()`, `dolt_version()`, `dolt_gc()` |

Anything not wrapped is still reachable, safely, through `dolt_scalar()` (for
`SELECT dolt_x(...)`) and `dolt_table()` (for `SELECT * FROM dolt_x(...)`).

All arguments are passed as **bound parameters**, never interpolated into SQL,
so a commit message containing quotes or semicolons is just a message.

## Documentation

* [Version-controlled data with doltliter](https://cathalbyrnegit.github.io/doltliter/articles/doltliter.html)
  — start here.
* [Branching, merging and conflicts](https://cathalbyrnegit.github.io/doltliter/articles/version-control.html)
* [Time travel: history, diffs and blame](https://cathalbyrnegit.github.io/doltliter/articles/time-travel.html)
* [Using dplyr](https://cathalbyrnegit.github.io/doltliter/articles/dplyr.html)
* [Installation and linking strategies](https://cathalbyrnegit.github.io/doltliter/articles/installation.html)

Design notes:
[DBI conformance](https://cathalbyrnegit.github.io/doltliter/articles/dbi-compliance.html)
(the full `DBItest` suite runs in the test suite and passes, apart from two
naming conventions that follow from the package's own name) and
[Why a native binding, and how it links](https://cathalbyrnegit.github.io/doltliter/articles/feasibility-notes.html)
(release artifacts, platform coverage, and why a CRAN submission would vendor
the amalgamation).

## License

MIT. DoltLite itself is distributed under its own terms; a package built from
the vendored amalgamation includes DoltLite and is subject to those too.
