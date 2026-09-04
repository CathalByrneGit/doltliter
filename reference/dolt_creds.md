# Credentials for authenticated remotes

Credentials for authenticated remotes

## Usage

``` r
dolt_creds(con, action = "export", id = NULL, path = NULL)

dolt_creds_new(con)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

- action:

  \`"export"\`.

- id:

  a credential id.

- path:

  a directory to export the public JWK into. Omit to have the JWK
  returned instead.

## Value

A string.
