# Using dplyr

[`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html) works
over a `doltliter` connection with no extra setup. DoltLite’s SQL
dialect *is* SQLite’s — the parser and planner are upstream, only the
storage engine below them differs — so this package reuses dbplyr’s
SQLite translation rather than defining its own.

``` r

library(doltliter)
library(dplyr)

con <- DBI::dbConnect(Doltlite(), tempfile(fileext = ".db"))
dolt_config(con, user.name = "Ada Lovelace", user.email = "ada@example.com")
```

## A lazy table

``` r

measurements <- data.frame(
  id     = 1:8,
  site   = rep(c("north", "south"), each = 4),
  season = rep(c("spring", "summer"), times = 4),
  value  = c(12.1, 15.4, 9.8, 11.2, 18.7, 22.3, 17.1, 19.9)
)

copy_to(con, measurements, "measurements", temporary = FALSE)
dolt_commit(con, "Load measurements")

tb <- tbl(con, "measurements")
tb
#> # A query:  ?? x 4
#> # Database: doltlite 3.54.0 [/tmp/RtmpfokiiO/file20824b4f5132.db@main]
#>      id site  season value
#>   <int> <chr> <chr>  <dbl>
#> 1     1 north spring  12.1
#> 2     2 north summer  15.4
#> 3     3 north spring   9.8
#> 4     4 north summer  11.2
#> 5     5 south spring  18.7
#> 6     6 south summer  22.3
#> 7     7 south spring  17.1
#> 8     8 south summer  19.9
```

The pipeline is not evaluated until you ask for the rows:

``` r

tb |>
  filter(value > 15) |>
  select(site, season, value) |>
  arrange(desc(value)) |>
  collect()
#> # A tibble: 5 × 3
#>   site  season value
#>   <chr> <chr>  <dbl>
#> 1 south summer  22.3
#> 2 south summer  19.9
#> 3 south spring  18.7
#> 4 south spring  17.1
#> 5 north summer  15.4
```

[`show_query()`](https://dplyr.tidyverse.org/reference/explain.html)
prints the SQL that would run, which is the quickest way to check that a
step is being pushed down rather than pulled into R:

``` r

tb |>
  group_by(site) |>
  summarise(n = n(), mean_value = mean(value, na.rm = TRUE)) |>
  show_query()
#> <SQL>
#> SELECT `site`, COUNT(*) AS `n`, AVG(`value`) AS `mean_value`
#> FROM `measurements`
#> GROUP BY `site`
```

``` r

tb |>
  group_by(site) |>
  summarise(n = n(), mean_value = mean(value, na.rm = TRUE)) |>
  collect()
#> # A tibble: 2 × 3
#>   site      n mean_value
#>   <chr> <int>      <dbl>
#> 1 north     4       12.1
#> 2 south     4       19.5
```

## Comparing branches with dplyr

This is where the combination gets interesting. A branch is just a
different view of the same file, so you can point two connections at two
branches and compare them with ordinary dplyr.

``` r

path <- DBI::dbGetInfo(con)$dbname

dolt_checkout(con, "reprocessed", create = TRUE)
DBI::dbExecute(con, "UPDATE measurements SET value = value * 1.1 WHERE site = 'north'")
#> [1] 4
dolt_commit(con, "Apply 10% correction to northern sites")
DBI::dbDisconnect(con)
```

Open one connection per branch:

``` r

main <- DBI::dbConnect(Doltlite(), path, branch = "main")
repro <- DBI::dbConnect(Doltlite(), path, branch = "reprocessed")

before <- tbl(main,  "measurements") |>
  group_by(site) |> summarise(mean_value = mean(value, na.rm = TRUE)) |> collect()

after <- tbl(repro, "measurements") |>
  group_by(site) |> summarise(mean_value = mean(value, na.rm = TRUE)) |> collect()

inner_join(before, after, by = "site", suffix = c("_main", "_reprocessed"))
#> # A tibble: 2 × 3
#>   site  mean_value_main mean_value_reprocessed
#>   <chr>           <dbl>                  <dbl>
#> 1 north            12.1                   13.3
#> 2 south            19.5                   19.5
```

Note that a join *across* two connections happens in R, because the two
[`tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)s belong to
different sources. Within one connection, joins are pushed down to SQL
as usual.

## Writing results back

[`compute()`](https://dplyr.tidyverse.org/reference/compute.html)
materialises a query into a table on the database, which then commits,
diffs and branches like any other:

``` r

summary_tbl <- tbl(repro, "measurements") |>
  group_by(site, season) |>
  summarise(mean_value = mean(value, na.rm = TRUE), .groups = "drop") |>
  compute(name = "site_season_summary", temporary = FALSE)

dolt_config(repro, user.name = "Ada Lovelace", user.email = "ada@example.com")
dolt_commit(repro, "Add site/season summary")
dolt_log(repro)$message[1]
#> [1] "Add site/season summary"
```

## A note on translation

dbplyr version-gates a handful of its SQLite translations and reads the
SQLite version from RSQLite. If RSQLite is not installed, `doltliter`
falls back to dbplyr’s default translation and says so once. Everything
still works; you just get slightly more generic SQL. Install RSQLite if
you want the full SQLite translation table.

``` r

DBI::dbDisconnect(main)
DBI::dbDisconnect(repro)
```
