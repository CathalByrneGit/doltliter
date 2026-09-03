#' @rdname DoltliteResult-class
#' @param res,dbObj a `DoltliteResult`.
#' @param ... unused.
#' @export
setMethod("dbIsValid", "DoltliteResult", function(dbObj, ...) {
  .Call(C_dltr_result_is_valid, dbObj@ptr)
})

#' @rdname DoltliteResult-class
#' @export
setMethod("dbClearResult", "DoltliteResult", function(res, ...) {
  if (!dbIsValid(res)) {
    warning("this result set has already been cleared", call. = FALSE)
    return(invisible(TRUE))
  }
  .Call(C_dltr_result_clear, res@ptr)
  invisible(TRUE)
})

#' @rdname DoltliteResult-class
#' @param n number of rows to fetch; `-1` (the default) means all remaining.
#' @export
setMethod("dbFetch", "DoltliteResult", function(res, n = -1, ...) {
  if (!dbIsValid(res)) stop("this result set has been cleared", call. = FALSE)
  if (!is.numeric(n) || length(n) != 1L || is.na(n)) {
    stop("`n` must be a single, non-NA number", call. = FALSE)
  }
  if (is.finite(n)) {
    if (n != trunc(n)) {
      stop("`n` must be a whole number, not ", n, call. = FALSE)
    }
    if (n < -1) stop("`n` must be -1 or a non-negative number", call. = FALSE)
  } else if (n < 0) {
    stop("`n` must be -1 or a non-negative number", call. = FALSE)
  }

  if (res@is_statement) {
    warning("this statement returns no rows", call. = FALSE)
    return(doltlite_empty_frame(character()))
  }

  cols <- .Call(C_dltr_result_fetch, res@ptr, as.numeric(n))
  doltlite_as_data_frame(cols)
})

#' @rdname DoltliteResult-class
#' @export
setMethod("dbHasCompleted", "DoltliteResult", function(res, ...) {
  if (!dbIsValid(res)) stop("this result set has been cleared", call. = FALSE)
  .Call(C_dltr_result_completed, res@ptr)
})

#' @rdname DoltliteResult-class
#' @export
setMethod("dbGetRowCount", "DoltliteResult", function(res, ...) {
  if (!dbIsValid(res)) stop("this result set has been cleared", call. = FALSE)
  n <- .Call(C_dltr_result_rows_fetched, res@ptr)
  if (n <= .Machine$integer.max) as.integer(n) else n
})

#' @rdname DoltliteResult-class
#' @export
setMethod("dbGetRowsAffected", "DoltliteResult", function(res, ...) {
  if (!dbIsValid(res)) stop("this result set has been cleared", call. = FALSE)
  # NA_integer_ when the statement has not run yet -- DBI specifies that,
  # rather than an error or a misleading 0.
  as.integer(.Call(C_dltr_result_rows_affected, res@ptr))
})

#' @rdname DoltliteResult-class
#' @export
setMethod("dbGetStatement", "DoltliteResult", function(res, ...) {
  if (!dbIsValid(res)) stop("this result set has been cleared", call. = FALSE)
  res@sql
})

#' @rdname DoltliteResult-class
#' @export
setMethod("dbColumnInfo", "DoltliteResult", function(res, ...) {
  if (!dbIsValid(res)) stop("this result set has been cleared", call. = FALSE)
  info <- .Call(C_dltr_result_column_info, res@ptr)
  data.frame(
    name = info$name,
    type = info$type,
    stringsAsFactors = FALSE
  )
})

#' @rdname DoltliteResult-class
#' @param params a list of parameter values.
#' @export
setMethod("dbBind", "DoltliteResult", function(res, params, ...) {
  if (!dbIsValid(res)) stop("this result set has been cleared", call. = FALSE)
  if (is.null(params)) params <- list()

  if (is.data.frame(params)) {
    params <- doltlite_prepare_params(params)
  } else if (is.list(params)) {
    nms <- names(params)
    params <- lapply(params, doltlite_coerce_param)
    names(params) <- nms
  } else if (is.atomic(params)) {
    # DBI accepts an atomic vector as one value per placeholder, so
    # dbBind(res, 1L) and dbBind(res, c(a = 1, b = 2)) both work.
    nms <- names(params)
    params <- lapply(as.list(params), doltlite_coerce_param)
    names(params) <- nms
  } else {
    stop("`params` must be a list, a data frame or an atomic vector",
         call. = FALSE)
  }
  .Call(C_dltr_result_bind, res@ptr, params)
  invisible(res)
})

#' @rdname DoltliteResult-class
#' @export
setMethod("show", "DoltliteResult", function(object) {
  cat("<DoltliteResult>\n")
  if (!dbIsValid(object)) {
    cat("  CLEARED\n")
    return(invisible(object))
  }
  cat("  SQL:  ", object@sql, "\n", sep = "")
  cat("  Rows fetched: ", dbGetRowCount(object), "\n", sep = "")
  invisible(object)
})

# --------------------------------------------------------------- internals ---

doltlite_empty_frame <- function(names) {
  out <- rep_len(list(logical()), length(names))
  names(out) <- names
  doltlite_as_data_frame(out)
}

# Build the data frame directly rather than via data.frame(), which would
# mangle names, coerce strings to factors on old R, and drop the list columns
# that carry blobs.
doltlite_as_data_frame <- function(cols) {
  n <- if (length(cols) == 0L) 0L else length(cols[[1L]])
  # The compact form, c(NA, -n): DBI requires automatic row names, and
  # seq_len(n) would record them as explicit ones.
  attr(cols, "row.names") <- c(NA_integer_, -n)
  class(cols) <- "data.frame"
  cols
}
