# DoltLite version

DoltLite version

## Usage

``` r
dolt_version(con)
```

## Arguments

- con:

  a \`DoltliteConnection\`.

## Value

The DoltLite version string.

Note that a package built from the DoltLite \*amalgamation\* reports
whatever version \`configure\` stamped in; a package linked against a
prebuilt library reports the version compiled into that library. Use
\[doltlite_engine()\] if all you need is to confirm the storage engine.
