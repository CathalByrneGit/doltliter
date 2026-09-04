# DBI conformance, driven by the DBItest package.
#
# Two checks are knowingly not met, both of them naming conventions rather
# than behaviour:
#
#   * "Getting started: package_name" expects the package name to start with
#     "R" (RSQLite, RMariaDB, ...). This package is called doltliter.
#   * "Driver: constructor" expects a constructor function named after the
#     package with that "R" stripped, i.e. doltliter(). The constructor here
#     is Doltlite(), matching the driver rather than the package.
#
# Both follow from the package and constructor names, and neither affects how
# the backend behaves. Everything else in the suite passes; see
# the "DBI conformance" article on the package website.
skip_if_not_installed("DBItest")

# DBItest's round-trip fixtures contain non-ASCII text (e.g. "Müller"), which a
# C/POSIX locale cannot represent. Running there reports encoding failures that
# say nothing about this backend, so require a UTF-8 locale.
skip_if_not(
  grepl("UTF-?8", Sys.getlocale("LC_CTYPE"), ignore.case = TRUE),
  "DBItest needs a UTF-8 locale"
)

DBItest::make_context(
  doltliter::Doltlite(),
  list(dbname = tempfile("doltliter-dbitest", fileext = ".db")),
  tweaks = DBItest::tweaks(
    constructor_relax_args = TRUE,
    placeholder_pattern = c("?", "$1", "$name", ":name"),
    # DoltLite inherits SQLite's type system: no native date, time or
    # timestamp types, so those round-trip as text or numbers.
    date_cast = function(x) paste0("'", x, "'"),
    time_cast = function(x) paste0("'", x, "'"),
    timestamp_cast = function(x) paste0("'", x, "'"),
    logical_return = function(x) as.integer(x),
    date_typed = FALSE,
    time_typed = FALSE,
    timestamp_typed = FALSE
  ),
  name = "doltliter"
)

DBItest::test_connection()
DBItest::test_result()
DBItest::test_sql()
DBItest::test_meta()
DBItest::test_transaction()
DBItest::test_compliance()
