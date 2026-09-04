# DoltLite result class

DoltLite result class

## Usage

``` r
# S4 method for class 'DoltliteResult'
dbIsValid(dbObj, ...)

# S4 method for class 'DoltliteResult'
dbClearResult(res, ...)

# S4 method for class 'DoltliteResult'
dbFetch(res, n = -1, ...)

# S4 method for class 'DoltliteResult'
dbHasCompleted(res, ...)

# S4 method for class 'DoltliteResult'
dbGetRowCount(res, ...)

# S4 method for class 'DoltliteResult'
dbGetRowsAffected(res, ...)

# S4 method for class 'DoltliteResult'
dbGetStatement(res, ...)

# S4 method for class 'DoltliteResult'
dbColumnInfo(res, ...)

# S4 method for class 'DoltliteResult'
dbBind(res, params, ...)

# S4 method for class 'DoltliteResult'
show(object)
```

## Arguments

- ...:

  unused.

- res, dbObj:

  a \`DoltliteResult\`.

- n:

  number of rows to fetch; \`-1\` (the default) means all remaining.

- params:

  a list of parameter values.

## Slots

- `ptr`:

  external pointer to the C result object.

- `conn`:

  the connection that produced this result.

- `sql`:

  the statement text.

- `is_statement`:

  whether the statement returns no columns.
