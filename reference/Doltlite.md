# Create a DoltLite driver object

\`Doltlite()\` creates the driver object passed to \[DBI::dbConnect()\].
It carries no state: connection options belong to \`dbConnect()\`.

## Usage

``` r
Doltlite()

# S4 method for class 'DoltliteDriver'
dbUnloadDriver(drv, ...)

# S4 method for class 'DoltliteDriver'
dbIsValid(dbObj, ...)

# S4 method for class 'DoltliteDriver'
show(object)

# S4 method for class 'DoltliteDriver'
dbGetInfo(dbObj, ...)
```

## Arguments

- drv, dbObj, object:

  a \`DoltliteDriver\`, as returned by \`Doltlite()\`.

- ...:

  unused, for compatibility with the DBI generics.

## Value

\`Doltlite()\` returns a \`DoltliteDriver\`. \`dbGetInfo()\` returns a
list describing the driver and the DoltLite build behind it.

## Examples

``` r
con <- DBI::dbConnect(doltliter::Doltlite(), ":memory:")
DBI::dbGetQuery(con, "SELECT doltlite_engine()")
#>   doltlite_engine()
#> 1            prolly
DBI::dbDisconnect(con)
```
