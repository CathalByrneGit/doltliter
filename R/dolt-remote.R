#' Manage remotes
#'
#' @param con a `DoltliteConnection`.
#' @param action `"add"` or `"remove"`. Omit to list remotes.
#' @param name the remote name, e.g. `"origin"`.
#' @param url a `file://` or `http(s)://` URL. The HTTP form includes the
#'   database name, e.g. `http://host:8080/mydb.db`.
#' @return A data frame when listing, otherwise invisibly `TRUE`.
#' @export
#' @examples
#' con <- DBI::dbConnect(doltliter::Doltlite(), tempfile())
#' dolt_remote(con)
#' DBI::dbDisconnect(con)
dolt_remote <- function(con, action = NULL, name = NULL, url = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_remote")

  if (is.null(action)) return(dolt_remotes(con))
  action <- match.arg(action, c("add", "remove"))
  if (is.null(name)) stop("`name` is required", call. = FALSE)
  if (action == "add") {
    if (is.null(url)) stop("`url` is required when adding a remote", call. = FALSE)
    dolt_scalar(con, "dolt_remote", "add", name, url)
  } else {
    dolt_scalar(con, "dolt_remote", "remove", name)
  }
  invisible(TRUE)
}

#' @rdname dolt_remote
#' @export
dolt_remotes <- function(con) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_remotes")
  dolt_table(con, "dolt_remotes")
}

#' Exchange commits with a remote
#'
#' @param con a `DoltliteConnection`.
#' @param remote the remote name, `"origin"` by default.
#' @param branch the branch to transfer. Omit for the remote's default
#'   behaviour.
#' @return The result string.
#' @export
dolt_push <- function(con, remote = "origin", branch = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_push")
  dolt_scalar(con, "dolt_push", remote, branch)
}

#' @rdname dolt_push
#' @export
dolt_fetch <- function(con, remote = "origin", branch = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_fetch")
  dolt_scalar(con, "dolt_fetch", remote, branch)
}

#' Fetch, then fast-forward or merge
#'
#' Fast-forwards when the local branch is an ancestor of the remote tip, and
#' three-way merges when it has diverged. A non-current branch that is not a
#' fast-forward is refused.
#'
#' @param con a `DoltliteConnection`.
#' @param remote the remote name.
#' @param branch the branch to pull.
#' @return The result string.
#' @export
dolt_pull <- function(con, remote = "origin", branch = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_pull")
  dolt_scalar(con, "dolt_pull", remote, branch)
}

#' Clone a remote database
#'
#' Called on an already-open connection: DoltLite clones into the connection's
#' own database.
#'
#' @param con a `DoltliteConnection`.
#' @param url the source URL.
#' @param lazy install refs and record `origin` without copying the reachable
#'   chunk graph, fetching chunks on demand instead. To reopen a lazy clone in
#'   another process, pass `dbname` as
#'   `"file:/path/to/db?lazy_origin=1"` with `flags` including SQLite's URI
#'   bit.
#' @return The result string.
#' @export
dolt_clone <- function(con, url, lazy = FALSE) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_clone")
  if (isTRUE(lazy)) {
    dolt_scalar(con, "dolt_clone", "--lazy", url)
  } else {
    dolt_scalar(con, "dolt_clone", url)
  }
}

#' Credentials for authenticated remotes
#'
#' @param con a `DoltliteConnection`.
#' @param action `"export"`.
#' @param id a credential id.
#' @param path a directory to export the public JWK into. Omit to have the
#'   JWK returned instead.
#' @return A string.
#' @export
dolt_creds <- function(con, action = "export", id = NULL, path = NULL) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_creds")
  if (is.null(id)) stop("`id` is required", call. = FALSE)
  dolt_scalar(con, "dolt_creds", action, id, path)
}

#' @rdname dolt_creds
#' @export
dolt_creds_new <- function(con) {
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_creds_new")
  dolt_scalar(con, "dolt_creds_new")
}
