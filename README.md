# doltliter

<!-- badges: start -->
[![R-CMD-check](https://github.com/CathalByrneGit/doltliter/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/CathalByrneGit/doltliter/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://github.com/CathalByrneGit/doltliter/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/CathalByrneGit/doltliter/actions/workflows/pkgdown.yaml)
<!-- badges: end -->


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

The package needs a `libdoltlite` to build against. `configure` finds one for
you, trying three strategies in order of cost:

1. **An installed DoltLite** — found via `pkg-config`, `DOLTLITE_HOME`,
   explicit `DOLTLITE_CFLAGS`/`DOLTLITE_LIBS`, or a common prefix
   (`/usr/local`, `/opt/homebrew`, …). Costs nothing, and is used
   automatically if you already have DoltLite installed:

   ```sh
   sudo bash -c 'curl -fsSL https://github.com/dolthub/doltlite/releases/latest/download/install.sh | bash'
   # or, on Debian/Ubuntu: install libdoltlite-dev
   ```

2. **A vendored amalgamation** — stage DoltLite's single-file amalgamation and
   compile it into the package. No network access at install time, and the
   DoltLite version is pinned exactly:

   ```sh
   Rscript tools/vendor_amalgamation.R
   R CMD INSTALL .
   ```

   This takes about a minute to compile and is the default on Windows and
   Intel macOS, where no usable prebuilt library is published.

3. **A downloaded release library** — `configure` fetches the prebuilt
   `libdoltlite` matching your OS and architecture from DoltLite's GitHub
   releases.

Force one with `DOLTLITER_STRATEGY=system|vendor|download`, and pin the
DoltLite version with `DOLTLITE_VERSION`. `configure` finishes by compiling and
running a small probe that asserts the engine really is `prolly`, so a build
that accidentally linked stock SQLite fails loudly at install time rather than
mysteriously at the first `dolt_*` call.

The background to all of this — what the release artifacts actually contain,
which platforms have no prebuilt library, and why Windows prefers the
amalgamation — is in
[Why a native binding, and how it links](https://cathalbyrnegit.github.io/doltliter/articles/feasibility-notes.html).

## Two kinds of "commit"

This is the one thing worth internalising before you start.

| | What it does | When it matters |
|---|---|---|
| `DBI::dbCommit()` | Ends a **SQL transaction**. Statements since `dbBegin()` either all apply or none do. | Atomicity of a batch of writes. |
| `dolt_commit()` | Writes a **commit into the version history**, like `git commit`. | Anything you want to diff, branch, or come back to. |

`dbCommit()` is "save the file"; `dolt_commit()` is "commit to the
repository". Data written and `dbCommit()`-ed is in the database but still
uncommitted as far as Dolt is concerned — it shows up in `dolt_status()` until
you call `dolt_commit()`.

One asymmetry: `dolt_commit()` also ends the enclosing SQL transaction, so
after calling it inside a `dbBegin()` block there is nothing left to
`dbCommit()`.

## What you get

**Standard DBI** — `dbConnect`, `dbDisconnect`, `dbGetQuery`, `dbSendQuery`,
`dbSendStatement`, `dbBind`, `dbFetch`, `dbColumnInfo`, `dbWriteTable`,
`dbReadTable`, `dbAppendTable`, `dbCreateTable`, `dbListTables`,
`dbListFields`, `dbExistsTable`, `dbRemoveTable`, `dbBegin`/`dbCommit`/
`dbRollback`, and the rest.

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

## Working on a branch

Pass `branch =` to connect straight onto one. It is translated to DoltLite's
`dbname@branch` path syntax internally:

```r
con <- DBI::dbConnect(doltliter::Doltlite(), "mydata.db", branch = "experiment")
active_branch(con)
#> [1] "experiment"
```

The branch must already exist. DoltLite would silently open `main` for a
database that does not have it; `doltliter` checks and errors instead.

Only the `@` form is emitted, never DoltLite's equivalent `db/branch` form,
which is impossible to tell apart from an ordinary path separator.

## dplyr and dbplyr

`dplyr::tbl()` and lazy query translation work out of the box — DoltLite's SQL
dialect *is* SQLite's, so the package reuses dbplyr's SQLite translation
rather than defining its own.

dbplyr version-gates a few of those translations by reading the SQLite version
from RSQLite. If RSQLite is not installed, `doltliter` falls back to dbplyr's
default translation and says so once. Install RSQLite if you want the full
SQLite translation table.

## Things to know

* **`dbname = ""`.** SQLite's anonymous temporary database is created in the
  *original* B-tree format, so version control is unavailable there. Use a
  real path (`tempfile()`) if you need it. The `dolt_*` functions say so
  explicitly rather than failing with "no such function".
* **Non-`INTEGER` primary keys are clustered.** Such a table has no `rowid` at
  all and its key columns are `NOT NULL`, as with SQLite's `WITHOUT ROWID`.
  The default `dbWriteTable()` declares no primary key, so this only bites if
  you ask for one via `field.types`.
* **One durable writer at a time.** A second concurrent writer gets
  `SQLITE_BUSY`; a transaction that tries to upgrade after a peer advanced the
  store gets `SQLITE_BUSY_SNAPSHOT`. Both are retryable. `dbConnect()` sets a
  5-second busy timeout by default (`busy_timeout =`).
* **Conflicting merges need a transaction.** Conflicts exist only inside the
  transaction that produced them, so an autocommit merge that conflicts is
  rolled back whole. See `?dolt_merge`.
* **Storage format is pinned.** DoltLite readers require an exact chunk-store
  format match and return `SQLITE_NOTADB` otherwise; `doltliter` translates
  that into a message saying so.

## Distribution

This package is distributed via GitHub. A `configure` script that downloads a
binary at install time is a common CRAN rejection reason — which is why
strategy 2 exists: staging the amalgamation with
`tools/vendor_amalgamation.R` produces a tree that builds with no network
access at all, which is the form a CRAN submission would take.

One thing to know before submitting that way: the vendored amalgamation
suppresses compiler diagnostics, as SQLite's own does, so `R CMD check`
reports `checking pragmas in C/C++ headers and code ... WARNING`. It is an
accurate statement about third-party generated source rather than a defect
here, and it cannot be resolved without editing that source. See
[Why a native binding, and how it links](https://cathalbyrnegit.github.io/doltliter/articles/feasibility-notes.html).

## DBI conformance

The full `DBItest` suite runs as part of the test suite and passes, apart from
two naming conventions that follow from the package's own name. Details in
[DBI conformance](https://cathalbyrnegit.github.io/doltliter/articles/dbi-compliance.html).

## License

MIT. DoltLite itself is distributed under its own terms; a package built from
the vendored amalgamation includes DoltLite and is subject to those too.
