# Stage tables

Stage tables

## Usage

``` r
dolt_add(con, tables = NULL, all = is.null(tables))
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- tables:

  table names to stage. Omit, or pass \`all = TRUE\`, to stage
  everything.

- all:

  stage all tables (\`dolt_add('-A')\`).

## Value

Invisibly \`TRUE\`.
