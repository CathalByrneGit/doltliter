#!/usr/bin/env Rscript
# Stage the DoltLite amalgamation into src/doltlite/ so that configure's
# "vendor" strategy can compile it.
#
#   Rscript tools/vendor_amalgamation.R            # pinned version
#   Rscript tools/vendor_amalgamation.R 0.50.3     # a specific version
#
# The amalgamation is ~20 MB of generated third-party C, so it is deliberately
# not committed to this repository; this script reproduces it on demand. Run it
# before building a CRAN-style source tarball that must compile without network
# access at install time.

args <- commandArgs(trailingOnly = TRUE)

# Run from the package root regardless of how we were invoked.
if (!file.exists("DESCRIPTION") && file.exists("../DESCRIPTION")) setwd("..")
if (!file.exists("DESCRIPTION")) {
  stop("run this from the doltliter package root", call. = FALSE)
}

version <- if (length(args) >= 1L) {
  args[[1L]]
} else if (nzchar(Sys.getenv("DOLTLITE_VERSION"))) {
  Sys.getenv("DOLTLITE_VERSION")
} else {
  trimws(readLines("tools/doltlite-version.txt", warn = FALSE)[[1L]])
}
version <- sub("^v", "", version)

base <- Sys.getenv(
  "DOLTLITE_BASE_URL",
  sprintf("https://github.com/dolthub/doltlite/releases/download/v%s", version)
)
name <- sprintf("doltlite-amalgamation-%s", version)
url  <- sprintf("%s/%s.zip", base, name)

dest_dir <- file.path("src", "doltlite")
zip_path <- tempfile(fileext = ".zip")
tmp_dir  <- tempfile()

message("doltliter: downloading ", url)
ok <- tryCatch({
  utils::download.file(url, zip_path, mode = "wb", quiet = FALSE)
  TRUE
}, error = function(e) {
  message("doltliter: download failed: ", conditionMessage(e))
  FALSE
})
if (!ok || !file.exists(zip_path)) {
  stop("could not download ", url, call. = FALSE)
}

dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
utils::unzip(zip_path, exdir = tmp_dir)

inner <- file.path(tmp_dir, name)
if (!dir.exists(inner)) {
  # Tolerate a flat archive layout.
  inner <- tmp_dir
}

need <- c("doltlite.c", "doltlite.h")
missing <- need[!file.exists(file.path(inner, need))]
if (length(missing)) {
  stop("the archive is missing: ", paste(missing, collapse = ", "), call. = FALSE)
}

dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
copy <- intersect(c("doltlite.c", "doltlite.h", "doltliteext.h"),
                  list.files(inner))
file.copy(file.path(inner, copy), file.path(dest_dir, copy), overwrite = TRUE)

# configure reads this to stamp -DDOLTLITE_VERSION, so that dolt_version()
# reports a real version rather than the amalgamation's placeholder.
#
# The name matters. This directory goes on the compiler's include path, and
# macOS filesystems are case-insensitive -- a file called VERSION here is found
# by libc++'s `#include <version>`, which then fails to compile the version
# string as C++. Any name that cannot collide with a standard header will do.
writeLines(paste0("v", version), file.path(dest_dir, "doltlite_version.txt"))

unlink(c(zip_path, tmp_dir), recursive = TRUE)

sizes <- file.info(file.path(dest_dir, copy))$size
message("doltliter: staged into ", dest_dir, ":")
for (i in seq_along(copy)) {
  message(sprintf("  %-16s %6.1f MB", copy[[i]], sizes[[i]] / 1024^2))
}
message("doltliter: version stamp v", version)
message("doltliter: now run  R CMD INSTALL .  (configure will pick up the vendor strategy)")
