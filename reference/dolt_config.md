# Configure the committer identity

Set or read the \`user.name\` / \`user.email\` used by
\[dolt_commit()\], \[dolt_merge()\], \[dolt_cherry_pick()\] and
\[dolt_revert()\].

## Usage

``` r
dolt_config(con, key = NULL, value = NULL, user.name = NULL, user.email = NULL)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- key:

  a setting name, e.g. \`"user.name"\`. Omit to read nothing.

- value:

  a value to set. Omit to read the current value instead.

- user.name, user.email:

  a convenience shorthand; supply either or both instead of
  \`key\`/\`value\`.

## Value

When reading, the value. When setting, invisibly \`TRUE\`.

## Details

Configuration is \*\*per connection\*\* and is not persisted. Set it
after connecting, on every connection that will commit.

## Examples

``` r
con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
dolt_config(con, user.name = "Ada Lovelace", user.email = "ada@example.com")
dolt_config(con, "user.name")
#> [1] "Ada Lovelace"
DBI::dbDisconnect(con)
```
