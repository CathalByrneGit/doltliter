# Tags

Tags

## Usage

``` r
dolt_tag(con, name = NULL, ref = NULL, delete = FALSE)

dolt_tags(con)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- name:

  the tag name. Omit to list tags.

- ref:

  the commit to tag; defaults to \`HEAD\`.

- delete:

  delete the tag instead of creating it.

## Value

A data frame when listing, otherwise invisibly \`TRUE\`.
