# Versioned views and triggers

Versioned views and triggers

## Usage

``` r
dolt_schemas(con)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

## Value

A data frame with \`type\`, \`name\`, \`fragment\`, \`extra\` and
\`sql_mode\`. Ordinary tables and indexes are not listed here; use
\`sqlite_schema\` or \[dolt_schema_diff()\] for the full schema surface.
