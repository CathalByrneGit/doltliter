#' @useDynLib doltliter, .registration = TRUE, .fixes = ""
NULL

.onLoad <- function(libname, pkgname) {
  # dbplyr is Suggested, so its S3 methods are registered here rather than in
  # NAMESPACE. See R/dbplyr.R.
  doltlite_register_dbplyr()
  invisible()
}

.onAttach <- function(libname, pkgname) {
  # A build that quietly linked stock libsqlite3 instead of libdoltlite would
  # otherwise fail much later, at the first dolt_* call, with a confusing
  # "no such function" error. configure checks this too, but a package can be
  # moved between machines after installation.
  engine <- tryCatch(doltlite_engine(), error = function(e) "")
  if (!identical(engine, "prolly")) {
    packageStartupMessage(
      "doltliter: this build reports engine '", engine,
      "' rather than 'prolly'.\n",
      "Version-control features will not be available. Reinstall the package ",
      "so that configure can find a real libdoltlite."
    )
  }
}

#' Library information
#'
#' @return `doltlite_engine()` returns the storage engine name, `"prolly"` for
#'   a DoltLite-format database. `doltlite_version()` returns the bundled
#'   SQLite version.
#' @export
doltlite_engine <- function() {
  .Call(C_dltr_engine)
}

#' @rdname doltlite_engine
#' @export
doltlite_version <- function() {
  .Call(C_dltr_libversion)
}

doltlite_build_info <- function() {
  .Call(C_dltr_build_info)
}
