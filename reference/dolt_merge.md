# Merge a branch into the current one

A three-way, row-level merge. Non-conflicting row edits merge
automatically; edits to the same row become conflicts.

## Usage

``` r
dolt_merge(con, name)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- name:

  the branch to merge in.

## Value

The merge commit hash on a clean merge, otherwise a string reporting the
conflict count. Errors if the merge conflicts outside a transaction,
since DoltLite rolls such a merge back whole.

## Conflicts require an explicit transaction

Conflicts are never durable in DoltLite: they exist only inside the
transaction that produced them. A merge run in autocommit mode – which
is what you get by default – is therefore \*\*rolled back in full\*\*
the moment it conflicts, and \`dolt_merge()\` raises an error rather
than returning a conflict count. There is then nothing left in
\`dolt_conflicts()\` to inspect, because nothing conflicted was kept.

To handle conflicts, wrap the merge in a transaction:

“\`r DBI::dbBegin(con) dolt_merge(con, "feature") \# returns a conflict
report dolt_conflicts(con) \# inspect dolt_conflicts_resolve(con,
"ours") \# or "theirs", or edit rows directly dolt_commit(con, "merge
feature") DBI::dbCommit(con) “\`

A commit is refused while any conflict remains. A merge that is expected
to be clean needs no transaction.

## See also

\[dolt_conflicts()\], \[doltliter-transactions\]
