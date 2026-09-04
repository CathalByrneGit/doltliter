# Package index

## Connecting

Opening a database, optionally straight onto a branch. `dbConnect()`
takes the DoltLite-specific `branch`, `bigint` and `busy_timeout`
arguments alongside the usual DBI ones.

- [`Doltlite()`](https://cathalbyrnegit.github.io/doltliter/reference/Doltlite.md)
  [`dbUnloadDriver(`*`<DoltliteDriver>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/Doltlite.md)
  [`dbIsValid(`*`<DoltliteDriver>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/Doltlite.md)
  [`show(`*`<DoltliteDriver>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/Doltlite.md)
  [`dbGetInfo(`*`<DoltliteDriver>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/Doltlite.md)
  : Create a DoltLite driver object
- [`dbConnect(`*`<DoltliteDriver>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/dbConnect-DoltliteDriver-method.md)
  : Connect to a DoltLite database
- [`DOLTLITE_RO`](https://cathalbyrnegit.github.io/doltliter/reference/DOLTLITE_RO.md)
  [`DOLTLITE_RW`](https://cathalbyrnegit.github.io/doltliter/reference/DOLTLITE_RO.md)
  [`DOLTLITE_RWC`](https://cathalbyrnegit.github.io/doltliter/reference/DOLTLITE_RO.md)
  : Database open flags

## DBI classes and methods

The ordinary DBI surface. These behave as they would for any SQLite
database, with the documented exceptions around clustered primary keys
and transactions.

- [`DoltliteDriver-class`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteDriver-class.md)
  : DoltLite driver class
- [`dbIsValid(`*`<DoltliteConnection>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbDisconnect(`*`<DoltliteConnection>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`show(`*`<DoltliteConnection>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbGetInfo(`*`<DoltliteConnection>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbSendQuery(`*`<DoltliteConnection>`*`,`*`<character>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbSendStatement(`*`<DoltliteConnection>`*`,`*`<character>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbGetQuery(`*`<DoltliteConnection>`*`,`*`<character>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbExecute(`*`<DoltliteConnection>`*`,`*`<character>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbListTables(`*`<DoltliteConnection>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbExistsTable(`*`<DoltliteConnection>`*`,`*`<character>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbListFields(`*`<DoltliteConnection>`*`,`*`<character>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbRemoveTable(`*`<DoltliteConnection>`*`,`*`<character>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbReadTable(`*`<DoltliteConnection>`*`,`*`<character>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbQuoteIdentifier(`*`<DoltliteConnection>`*`,`*`<character>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbQuoteIdentifier(`*`<DoltliteConnection>`*`,`*`<SQL>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbQuoteString(`*`<DoltliteConnection>`*`,`*`<character>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbQuoteString(`*`<DoltliteConnection>`*`,`*`<SQL>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbExistsTable(`*`<DoltliteConnection>`*`,`*`<SQL>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbListFields(`*`<DoltliteConnection>`*`,`*`<SQL>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbReadTable(`*`<DoltliteConnection>`*`,`*`<SQL>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  [`dbRemoveTable(`*`<DoltliteConnection>`*`,`*`<SQL>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteConnection-class.md)
  : DoltLite connection class
- [`dbIsValid(`*`<DoltliteResult>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteResult-class.md)
  [`dbClearResult(`*`<DoltliteResult>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteResult-class.md)
  [`dbFetch(`*`<DoltliteResult>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteResult-class.md)
  [`dbHasCompleted(`*`<DoltliteResult>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteResult-class.md)
  [`dbGetRowCount(`*`<DoltliteResult>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteResult-class.md)
  [`dbGetRowsAffected(`*`<DoltliteResult>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteResult-class.md)
  [`dbGetStatement(`*`<DoltliteResult>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteResult-class.md)
  [`dbColumnInfo(`*`<DoltliteResult>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteResult-class.md)
  [`dbBind(`*`<DoltliteResult>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteResult-class.md)
  [`show(`*`<DoltliteResult>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/DoltliteResult-class.md)
  : DoltLite result class
- [`dbWriteTable(`*`<DoltliteConnection>`*`,`*`<character>`*`,`*`<data.frame>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/dbWriteTable-DoltliteConnection-character-data.frame-method.md)
  [`dbCreateTable(`*`<DoltliteConnection>`*`,`*`<character>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/dbWriteTable-DoltliteConnection-character-data.frame-method.md)
  [`dbAppendTable(`*`<DoltliteConnection>`*`,`*`<character>`*`,`*`<data.frame>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/dbWriteTable-DoltliteConnection-character-data.frame-method.md)
  [`dbWriteTable(`*`<DoltliteConnection>`*`,`*`<SQL>`*`,`*`<data.frame>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/dbWriteTable-DoltliteConnection-character-data.frame-method.md)
  [`dbCreateTable(`*`<DoltliteConnection>`*`,`*`<SQL>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/dbWriteTable-DoltliteConnection-character-data.frame-method.md)
  [`dbAppendTable(`*`<DoltliteConnection>`*`,`*`<SQL>`*`,`*`<data.frame>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/dbWriteTable-DoltliteConnection-character-data.frame-method.md)
  : Write a data frame to a table
- [`dbDataType(`*`<DoltliteDriver>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/dbDataType-DoltliteDriver-method.md)
  [`dbDataType(`*`<DoltliteConnection>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/dbDataType-DoltliteDriver-method.md)
  : SQL type for an R object
- [`dbBegin(`*`<DoltliteConnection>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/doltliter-transactions.md)
  [`dbCommit(`*`<DoltliteConnection>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/doltliter-transactions.md)
  [`dbRollback(`*`<DoltliteConnection>`*`)`](https://cathalbyrnegit.github.io/doltliter/reference/doltliter-transactions.md)
  : Transactions

## Configuring and committing

The commit loop. Note that
[`dolt_commit()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_commit.md)
is the *Dolt* sense of commit — it writes to the version history — and
is unrelated to
[`DBI::dbCommit()`](https://dbi.r-dbi.org/reference/transactions.html).

- [`dolt_config()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_config.md)
  : Configure the committer identity
- [`dolt_add()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_add.md)
  : Stage tables
- [`dolt_commit()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_commit.md)
  : Commit the current working set
- [`dolt_status()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_status.md)
  : Working-set status
- [`dolt_reset()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_reset.md)
  : Undo uncommitted work
- [`dolt_revert()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_revert.md)
  : Revert a commit
- [`dolt_cherry_pick()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_cherry_pick.md)
  : Cherry-pick a commit

## Branches, merging and conflicts

Each connection selects its own branch. Conflicts exist only inside the
transaction that produced them, so a merge you expect to conflict
belongs in one.

- [`dolt_branch()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_branch.md)
  [`dolt_branches()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_branch.md)
  : Create, list or delete branches
- [`dolt_checkout()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_checkout.md)
  : Switch branches
- [`dolt_active_branch()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_active_branch.md)
  [`active_branch()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_active_branch.md)
  : The current branch
- [`dolt_merge()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_merge.md)
  : Merge a branch into the current one
- [`dolt_merge_base()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_merge_base.md)
  : Merge base of two commits
- [`dolt_merge_status()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_merge_status.md)
  : Merge status
- [`dolt_rebase()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_rebase.md)
  : Rebase the current branch onto another
- [`dolt_tag()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_tag.md)
  [`dolt_tags()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_tag.md)
  : Tags
- [`dolt_conflicts()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_conflicts.md)
  [`dolt_conflicts_table()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_conflicts.md)
  [`dolt_conflicts_resolve()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_conflicts.md)
  : Conflicts
- [`dolt_constraint_violations()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_constraint_violations.md)
  : Constraint violations left by a merge

## History, diffs and time travel

Reading the past: what changed, when, who changed it, and what a table
looked like at any revision.

- [`dolt_log()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_log.md)
  : Commit history
- [`dolt_diff()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_diff.md)
  : Which tables changed, per commit
- [`dolt_table_diff()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_table_diff.md)
  : Row-level differences for one table
- [`dolt_diff_stat()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_diff_stat.md)
  [`dolt_diff_summary()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_diff_stat.md)
  [`dolt_schema_diff()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_diff_stat.md)
  : Diff statistics and summaries
- [`dolt_patch()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_patch.md)
  : Executable patch between two refs
- [`dolt_history()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_history.md)
  : Every version of every row in a table
- [`dolt_at()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_at.md)
  : A table as it existed at a given revision
- [`dolt_blame()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_blame.md)
  : Which commit last set each row
- [`dolt_workspace()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_workspace.md)
  : Row-level working and staged edits
- [`dolt_schemas()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_schemas.md)
  : Versioned views and triggers

## Remotes

Push, pull, fetch and clone over the filesystem or HTTP.

- [`dolt_remote()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_remote.md)
  [`dolt_remotes()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_remote.md)
  : Manage remotes
- [`dolt_push()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_push.md)
  [`dolt_fetch()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_push.md)
  : Exchange commits with a remote
- [`dolt_pull()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_pull.md)
  : Fetch, then fast-forward or merge
- [`dolt_clone()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_clone.md)
  : Clone a remote database
- [`dolt_creds()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_creds.md)
  [`dolt_creds_new()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_creds.md)
  : Credentials for authenticated remotes

## Introspection and maintenance

- [`dolt_hashof()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_hashof.md)
  [`dolt_hashof_table()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_hashof.md)
  [`dolt_hashof_db()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_hashof.md)
  : Content-addressed hashes
- [`dolt_version()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_version.md)
  : DoltLite version
- [`doltlite_engine()`](https://cathalbyrnegit.github.io/doltliter/reference/doltlite_engine.md)
  [`doltlite_version()`](https://cathalbyrnegit.github.io/doltliter/reference/doltlite_engine.md)
  : Library information
- [`dolt_gc()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_gc.md)
  : Garbage-collect unreachable chunks
- [`dolt_verify_constraints()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_verify_constraints.md)
  : Re-check constraints

## Calling anything else

DoltLite’s version-control surface is split between scalar SQL functions
and virtual tables. These two helpers reach whichever part this package
does not wrap yet, with arguments bound as parameters rather than pasted
into SQL.

- [`dolt_scalar()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_scalar.md)
  : Call a Dolt scalar SQL function
- [`dolt_table()`](https://cathalbyrnegit.github.io/doltliter/reference/dolt_table.md)
  : Query a Dolt virtual table or table-valued function

## Re-exported from DBI

- [`reexports`](https://cathalbyrnegit.github.io/doltliter/reference/reexports.md)
  [`Id`](https://cathalbyrnegit.github.io/doltliter/reference/reexports.md)
  [`SQL`](https://cathalbyrnegit.github.io/doltliter/reference/reexports.md)
  [`dbCanConnect`](https://cathalbyrnegit.github.io/doltliter/reference/reexports.md)
  [`dbIsReadOnly`](https://cathalbyrnegit.github.io/doltliter/reference/reexports.md)
  [`dbListObjects`](https://cathalbyrnegit.github.io/doltliter/reference/reexports.md)
  [`dbQuoteLiteral`](https://cathalbyrnegit.github.io/doltliter/reference/reexports.md)
  [`dbUnquoteIdentifier`](https://cathalbyrnegit.github.io/doltliter/reference/reexports.md)
  [`dbWithTransaction`](https://cathalbyrnegit.github.io/doltliter/reference/reexports.md)
  : Objects re-exported from DBI
