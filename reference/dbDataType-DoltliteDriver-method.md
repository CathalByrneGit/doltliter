# SQL type for an R object

DoltLite uses SQLite's type names and affinity rules, so the mapping is
SQLite's. The one addition is \`integer64\`, which maps to \`INTEGER\`
because SQLite integers are already 64-bit.

## Usage

``` r
# S4 method for class 'DoltliteDriver'
dbDataType(dbObj, obj, ...)

# S4 method for class 'DoltliteConnection'
dbDataType(dbObj, obj, ...)
```

## Arguments

- dbObj:

  a driver or connection

- obj:

  an R object

- ...:

  unused
