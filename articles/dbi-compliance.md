# DBI conformance

`doltliter` runs the full [DBItest](https://dbitest.r-dbi.org) suite as
part of its own test suite (`tests/testthat/test-dbi-compliance.R`),
covering the `connection`, `result`, `sql`, `meta`, `transaction` and
`compliance` sections.

**Everything passes** except two checks, both naming conventions rather
than behaviour. They are listed below with the reasoning, rather than
skipped quietly.

## Deliberate non-conformance

### 1. `Getting started: package_name`

DBItest expects a backend package’s name to begin with `R` (RSQLite,
RMariaDB, RPostgres). This package is called `doltliter`.

The name is a deliberate choice: it reads as “DoltLite for R” and
matches the upstream project’s own naming for its bindings
(`doltlite-python`, `doltlite-ruby`, `doltlite-node`). Renaming to
`Rdoltlite` purely to satisfy a regular expression would make it harder
to find, not easier.

Nothing depends on this: no DBI machinery derives behaviour from the
package name.

### 2. `Driver: constructor`

Having stripped that leading `R`, DBItest then expects a constructor
function named after the package — `doltliter()`. The constructor here
is
[`Doltlite()`](https://cathalbyrnegit.github.io/doltliter/reference/Doltlite.md),
named after the *driver* rather than the package, so that
`DBI::dbConnect(doltliter::Doltlite(), ...)` reads the way
`DBI::dbConnect(RSQLite::SQLite(), ...)` does.

Exporting a second name for the same object would close the gap, at the
cost of two ways to spell one thing. That did not seem like a good trade
for a convention check.

## Tweaks, and why each is set

These are in
[`DBItest::tweaks()`](https://dbitest.r-dbi.org/reference/tweaks.html)
in the compliance test:

| Tweak | Reason |
|----|----|
| `constructor_relax_args = TRUE` | [`Doltlite()`](https://cathalbyrnegit.github.io/doltliter/reference/Doltlite.md) takes no arguments; connection options belong to `dbConnect()`. |
| `placeholder_pattern = c("?", "$1", "$name", ":name")` | The placeholder styles SQLite (and so DoltLite) actually accepts. |
| `date_cast`, `time_cast`, `timestamp_cast` | DoltLite inherits SQLite’s type system, which has no date/time types; these round-trip as text. |
| `date_typed`, `time_typed`, `timestamp_typed = FALSE` | Same reason: there is no typed date/time to test for. |
| `logical_return = as.integer` | SQLite has no boolean type; `TRUE` comes back as `1L`. |

The suite is skipped outside a UTF-8 locale, because DBItest’s own
round-trip fixtures contain non-ASCII text (`"Müller"`) that a C/POSIX
locale cannot represent. That is a property of the test environment, not
the backend — the backend validates UTF-8 on the way out and falls back
to the native encoding for bytes that are not valid UTF-8, precisely so
that it behaves in such a locale.

## Behaviours that are DoltLite’s, not DBI’s

These are not conformance failures — DBI does not specify them — but
they will surprise someone expecting RSQLite:

- **[`dolt_commit()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_commit.md)
  ends the enclosing SQL transaction.** `doltliter` reads transaction
  state from `sqlite3_get_autocommit()` rather than tracking it in R, so
  `dbBegin()`/`dbCommit()` stay accurate when this happens.
- **A conflicting merge in autocommit mode is rolled back entirely.**
  Conflicts are never durable in DoltLite.
  [`dolt_merge()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_merge.md)
  returns a conflict report when run inside a transaction and raises
  otherwise. See
  [`?dolt_merge`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_merge.md).
- **`dbname = ""` is not version controlled.** SQLite’s anonymous
  temporary database is created in the original B-tree format, where the
  `dolt_*` functions do not exist.
- **`PRAGMA journal_mode`** reports `wal` for a file-backed database and
  ignores attempts to change it; there is no WAL sidecar.
- **`dbstat` is unsupported** on a DoltLite-format database, and
  `sqlite_master.sql` is a canonicalised projection of the prolly
  catalog rather than verbatim DDL — so do not assert on exact DDL text.
- **A transaction may write only one file-backed database.**
  Multi-database writes are rejected outright.

## Reproducing

``` r

# The suite needs a UTF-8 locale.
Sys.setlocale("LC_CTYPE", "C.UTF-8")
testthat::test_file("tests/testthat/test-dbi-compliance.R")
```
