# Why a native binding, and how it links

Investigation date: 2026-09-03. Upstream studied: `dolthub/doltlite` @
`master` (shallow clone), release **v0.50.3** (bundled SQLite
**3.54.0**, chunk-store format **v12**, “beta”).

Everything below was **executed**, not inferred from documentation.
Where the upstream README and the actual release artifacts disagree, the
artifacts win and the disagreement is called out.

------------------------------------------------------------------------

## 1. Verdict

Native binding is **viable**. R links `libdoltlite` and drives the full
version-control surface. The `reticulate` fallback (option 3 in the
brief) is **not needed** and is not pursued.

Two independent link paths were proven end to end:

| Path | Result | Notes |
|----|----|----|
| Prebuilt `libdoltlite.a` from the release lib zip | **works** | link \< 1 s |
| Vendored single-file amalgamation (`doltlite.c`) | **works** | 71 s compile at `-O2`, 4.1 MB object |

Both produced identical behaviour from R and from plain C.

## 2. What R actually did

A throwaway package (`dlprobe`, plain `.Call` + `R_init_dlprobe`, no
Rcpp) compiled `#include <doltlite.h>` and linked `libdoltlite.a` with
`PKG_LIBS = .../libdoltlite.a -lpthread -lz -lm`. `R CMD INSTALL`
succeeded unmodified, and from an R session:

    engine       : prolly
    dolt_version : v0.50.3
    sqlite ver   : 3.54.0
    branch       : main

A fuller C probe drove a complete round trip against both link paths —
`dolt_config` → `CREATE TABLE` → `dolt_commit('-Am', ...)` →
`dolt_branch` → `dolt_checkout` → `UPDATE` → `dolt_commit` →
`dolt_diff_users('main','experiment')` → `dolt_checkout('main')` →
`dolt_merge('experiment')` — and the merged table contained the expected
rows. So the version-control features are reachable purely as SQL over
the ordinary `sqlite3_*` API, which is what makes Phase 4 a thin R layer
rather than new C bindings.

## 3. Release artifacts (verified against the v0.50.3 asset list)

    doltlite-amalgamation-0.50.3.zip      doltlite-lib-linux-x64-0.50.3.zip
    doltlite-autoconf-0.50.3.tar.gz       doltlite-lib-linux-arm64-0.50.3.zip
    doltlite-lib-osx-arm64-0.50.3.zip     doltlite-lib-win-x64-0.50.3.zip
    doltlite-tools-{linux-x64,linux-arm64,osx-arm64,win-x64}-0.50.3.zip
    doltlite{,-dev,0}_0.50.3_{amd64,arm64}.deb        install.sh
    doltlite-0.50.3.xcframework.zip       doltlite-wasm-0.50.3.zip

Three findings that change the `configure` design:

1.  **A Windows lib zip *does* exist** —
    `doltlite-lib-win-x64-0.50.3.zip`. The README’s Windows section
    mentions only `doltlite.exe`, so the brief’s open question (“only
    the CLI `.exe`?”) is answered: the README is incomplete.
2.  **But that zip ships only `libdoltlite.dll`** — no `.a`, no `.lib`,
    and **no `.dll.a` import library**. So “prebuilt Windows lib” does
    not mean “drop-in linkable with Rtools”. This is why `configure.win`
    prefers the amalgamation (below) rather than the prebuilt lib.
3.  **There is no `osx-x64` lib asset.** `install.sh` lists `osx-x64`
    among supported targets, but no such asset is published. Intel macOS
    therefore has *no* prebuilt lib and must use the amalgamation.

The amalgamation zip contains exactly three files — `doltlite.c` (19.7
MB), `doltlite.h` (698 KB), `doltliteext.h` — i.e. the same shape as
SQLite’s amalgamation that RSQLite vendors.

## 4. Chosen strategy: a three-tier `configure`

The brief ranked “download a prebuilt lib at install time” first and
noted that static vendoring is the CRAN-safe alternative. Because the
amalgamation compiles cleanly in 71 s, we get both, and neither is a
fallback for a *failure* of the other — they are ordered by cost:

1.  **Tier 1 — use an existing `libdoltlite`.**
    `pkg-config --exists doltlite`, then `DOLTLITE_HOME`, then explicit
    `DOLTLITE_CFLAGS`/`DOLTLITE_LIBS`, then common prefixes
    (`/usr/local`, `/usr`, `/opt/homebrew`, `/opt/local`). Costs
    nothing, honours a user’s `.deb`/Homebrew/`make install`.
2.  **Tier 2 — compile a vendored amalgamation** from
    `src/doltlite/doltlite.c` when present. No network, deterministic,
    exact version pinning. **This is the CRAN path**, and the default on
    Windows and Intel macOS.
3.  **Tier 3 — download the matching release lib zip** and link it. Best
    UX for `remotes::install_github()` on a machine with no system
    install.

`DOLTLITER_STRATEGY=system|vendor|download` forces one tier;
`DOLTLITE_VERSION` pins the version used by tiers 2 and 3.

The 19.7 MB `doltlite.c` is *not* committed to this repository — it is
generated third-party source. `tools/vendor_amalgamation.R` fetches and
stages it into `src/doltlite/`, so the CRAN path is reproducible without
carrying the blob in git history.

### Version stamping (a real trap)

[`dolt_version()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_version.md)
is compiled in from `git describe`. Built from the amalgamation it
returns the literal string **`doltlite-amalgamation`**, not a version.
Any release-pinning check keyed on
[`dolt_version()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_version.md)
therefore breaks on exactly the build path we recommend for CRAN. The
fix is to compile with `-DDOLTLITE_VERSION='"vX.Y.Z"'`, which
`configure` does from the staged version file.
[`doltlite_engine()`](https://cathalbyrnegit.github.io/doltliter/reference/doltlite_engine.md)
(returns `prolly`) and `sqlite3_libversion()` (`3.54.0`) are reliable
regardless of build path and are what `.onLoad`/ `dbGetInfo` should lean
on.

## 5. ABI and version pinning

Format version **12** is frozen for the beta, and **readers require an
exact `CHUNK_STORE_VERSION` match** — a mismatch returns `SQLITE_NOTADB`
with no silent reinterpretation. So the risk is not C-ABI drift (the
surface is SQLite’s own `sqlite3_*`, plus four exported
`doltlite*`/`doltliteServe*` symbols) but *file*-format drift. Any file
written by a version-12 build stays readable by later version-12 builds.

Practical consequence: pin a known-good DoltLite version for tiers 2 and
3, report the resolved version from `dbGetInfo()`, and treat
`SQLITE_NOTADB` on open as “database written by a different DoltLite
format version” in the error message, because that is overwhelmingly
what it means here.

Note also that the shared library **hides** prolly/chunk-store internals
and exports only `sqlite3_*`, `doltliteServe*`,
`doltlite_set_chunk_source`, and `doltlite_init_lazy`; the static
archive is unfiltered. We only need `sqlite3_*`, so either works.

## 6. Behaviours the DBI layer must accommodate

Measured with a purpose-built shell (`dlsh`) linked against the static
lib.

- **`dbWriteTable`’s default `CREATE TABLE` is safe.** A table with no
  primary key keeps a working `rowid` (`SELECT rowid, * FROM norow`
  returned `1|1|x`), so RSQLite’s table-creation logic needs no change
  for the common path.
- **Non-`INTEGER` primary keys are clustered.** `pragma_table_info`
  reports `notnull=1` on the PK, and `INSERT INTO t2(rowid,...)` fails
  at *prepare* time with `table t2 has no column named rowid`. This only
  bites when a user supplies such a PK — but
  `dbWriteTable(..., field.types=)` can, so it must be documented rather
  than discovered.
- **Explicit `WITHOUT ROWID` works** as in SQLite.
- **`PRAGMA journal_mode`** returns `wal` for a file-backed database and
  `memory` for `:memory:`, and ignores attempts to change it.
- **Transactions behave normally**: `BEGIN`/`COMMIT`/`ROLLBACK` and
  `BEGIN IMMEDIATE` all worked. These are SQLite transactions and are
  **unrelated to `dolt_commit`** — the two senses of “commit” must be
  documented prominently.
- **One durable writer at a time**: a second concurrent writer gets
  `SQLITE_BUSY`, and a read-snapshot transaction that tries to upgrade
  after a peer advanced the store gets `SQLITE_BUSY_SNAPSHOT`. The
  backend needs a busy timeout and should surface these as retryable.
- **`dbstat` is unsupported** on DoltLite-format databases (errors
  rather than reporting empty), and `sqlite_master.sql` is a
  *canonicalized* projection of the prolly catalog, not verbatim DDL —
  so tests must not assert exact DDL text.
- **A transaction may write only one file-backed database**;
  multi-database writes are rejected wholesale. Relevant to
  `ATTACH`-based `DBItest` cases.

### Result shapes (needed for Phase 4 wrappers)

| Relation | Columns |
|----|----|
| `dolt_status` | `table_name, staged, status` |
| `dolt_log` | `commit_hash, committer, email, date, message` |
| `dolt_branches` | `name, hash, latest_committer, latest_committer_email, latest_commit_date, latest_commit_message, remote, branch, dirty` |
| `dolt_diff` | `commit_hash, committer, email, date, message, data_change, schema_change, table_name` |

`dolt_commit` returns the new commit hash as text; `dolt_config` returns
`0`.

**Critical shape distinction for Phase 4:** the version-control surface
is split between *scalar functions* (`dolt_commit`, `dolt_branch`,
`dolt_checkout`, `dolt_merge`, `dolt_config`, `active_branch`, …),
called as `SELECT dolt_x(...)`, and *virtual tables / table-valued
functions* (`dolt_log`, `dolt_status`, `dolt_diff`, `dolt_diff_<table>`,
`dolt_history_<table>`, `dolt_blame_<table>`, `dolt_diff_stat`,
`dolt_patch`, …), which must be called as `SELECT * FROM dolt_x(...)`.
The sketch in the brief uses the scalar form throughout; applying it to
`dolt_log`/`dolt_diff` would not work. The helper layer therefore has
two constructors, not one.

## 7. Branch-suffix paths and R path handling

`sqlite3_open("my.db@feature")` selects a branch; `my.db/feature` does
the same, and `my.db/<tag|hash|main~1>` opens a **read-only detached
snapshot** where
[`active_branch()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_active_branch.md)
is `NULL`.

The `/` form is ambiguous with an ordinary path separator and cannot be
disentangled reliably on either platform, so `doltliter` **always emits
the `@` form** internally and takes the branch as an explicit `branch =`
argument. `dbname` is expanded (`path.expand`) but deliberately **not**
`normalizePath`-ed with a suffix attached, since a `db@branch` string is
not an existing file. An `@` in the `dbname` itself is honoured as
user-supplied revision syntax, and supplying both that and `branch =` is
an error rather than a silent precedence rule.

## 8. Consequences for the rest of the plan

- Phases 2–5 proceed as written; the `reticulate` pivot is off the table
  and the package keeps the name `doltliter`.
- Phase 4 is SQL-only, as the brief predicted — confirmed by driving the
  whole commit/branch/merge loop through `sqlite3_prepare_v2`/`step`
  alone.
- Phase 6’s CRAN-vs-GitHub tension is resolved by tier 2 existing:
  GitHub installs get tiers 1/3 for speed, and a CRAN submission ships
  the vendored amalgamation with no install-time download.

------------------------------------------------------------------------

## Appendix: confirmed during implementation

The plan above survived contact with the code. All three `configure`
tiers were built and run end to end on Linux x86_64:

| Tier | Result |
|----|----|
| `system` (prefix `/usr/local`) | installs, [`doltlite_engine()`](https://cathalbyrnegit.github.io/doltliter/reference/doltlite_engine.md) → `prolly` |
| `vendor` (amalgamation) | installs, [`dolt_version()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_version.md) → `v0.50.3` via the version stamp |
| `download` (release lib zip) | installs, full commit/branch round trip |

A golden-file check against the `doltlite` CLI
(`tools/golden_file_check.R`) reports byte-identical
[`dolt_hashof_table()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_hashof.md)
and
[`dolt_hashof_db()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_hashof.md)
values for databases built independently through the CLI and through the
package.

A handful of behaviours only surfaced once real code exercised them.
They are recorded here because each one is a trap for the next person:

- **[`dolt_commit()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_commit.md)
  ends the enclosing SQL transaction.** Any R-side flag tracking
  transaction state goes stale the moment it is called, so the backend
  reads `sqlite3_get_autocommit()` instead.

- **A conflicting merge in autocommit mode is rolled back whole**, and
  DoltLite reports the conflict as a SQL *error* rather than a return
  value — in both autocommit and transaction modes.
  [`dolt_merge()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_merge.md)
  therefore distinguishes the two by checking whether conflicts actually
  survived.

- **`dolt_blame_<table>` requires a primary key.** There is no stable
  row identity to attribute changes to without one, and
  `dbWriteTable()`’s default `CREATE TABLE` declares no key.

- **Commit hashes cover the commit timestamp**, so they are not
  reproducible across two independently built databases.
  [`dolt_hashof_table()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_hashof.md)
  and
  [`dolt_hashof_db()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_hashof.md)
  are, which is what makes them usable as a golden file.

- **[`dolt_config()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_config.md)
  is per connection and not persisted**, which also means a CLI
  comparison must pipe its whole script through a single process.

- **DoltLite bundles its own zlib**: linking needs neither `-lz` nor
  `-lpthread` on Linux, only `-lm`. `configure` still tries the longer
  candidate link lines, since older layouts and static archives may want
  them.

- **Never put an extensionless file in a directory that is on the
  include path.** `tools/vendor_amalgamation.R` originally wrote the
  version stamp to `src/doltlite/VERSION`, and `configure` puts that
  directory on the include path with `-I./doltlite`. macOS filesystems
  are case-insensitive, so libc++’s `#include <version>` – reached from
  `<cstddef>`, itself reached from `<set>` – resolved to that stamp and
  clang tried to compile `v0.50.3` as C++. It only bit macOS + vendor:
  Linux is case-sensitive, libstdc++ does not chain `<version>` from
  `<cstddef>`, and the macOS ARM job uses the prebuilt library so the
  file is not there at all. The stamp is now `doltlite_version.txt`.

- **dbplyr’s SQLite translation reads the SQLite version from RSQLite**,
  and builds that table lazily, so a missing RSQLite fails at
  query-render time rather than at dialect construction. The backend
  checks for RSQLite up front and degrades to dbplyr’s default
  translation rather than taking a hard dependency on another SQLite
  backend.

### Known trade-off: the vendored amalgamation trips R’s pragma check

`R CMD check --as-cran` on a tree carrying the amalgamation reports:

    * checking pragmas in C/C++ headers and code ... WARNING
    File which contains non-portable pragma(s)
      'src/doltlite/doltlite.c'
    File which contains pragma(s) suppressing diagnostics:
      'src/doltlite/doltlite.c'

This is accurate: DoltLite’s generated amalgamation does suppress
compiler diagnostics, as SQLite’s own amalgamation does.
`tools:::.check_pragmas()` scans `src/` and `inst/include` recursively
for `#pragma (GCC|clang) diagnostic ignored` and for a list of
non-portable warning names, and there is no environment variable to
switch it off.

It cannot be fixed from this side without editing third-party generated
source, which would be worse than the warning. Three consequences:

- **CI**: the vendor jobs run with `error-on: error` rather than the
  default `error-on: warning`, since otherwise a warning that is not
  this package’s to fix would fail them. A guard step then rejects any
  *other* warning, so this is not a blanket amnesty.
- **CRAN**: a submission shipping the amalgamation will carry this
  warning and will need it explained in the submission comments. That is
  the price of the no-network install path; the `system` and `download`
  strategies do not trigger it, because the engine arrives prebuilt with
  no C sources to scan.
- It is a WARNING, not an ERROR, and it does not affect the built
  package.

### Known trade-off: installed size

Statically linking `libdoltlite.a` (38 MB on disk, ~19 MB linked) makes
the installed package about 19 MB, which `R CMD check` flags as a NOTE.
That is inherent to embedding the engine, and is the same trade RSQLite
makes with `sqlite3.c`; linking the shared library instead would shrink
the package but move the problem to runtime library resolution.
