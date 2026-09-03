# DBI asks a compliant backend to re-export these, so that attaching doltliter
# is enough to use them. They are documented here rather than left as bare
# exports, which R CMD check rightly objects to.

#' Objects re-exported from DBI
#'
#' These are DBI's own functions, re-exported so that they are available after
#' `library(doltliter)` without attaching DBI as well. See the linked DBI
#' documentation for each.
#'
#' @name reexports
#' @keywords internal
#' @param ... passed on to the DBI function.
#' @return As documented by DBI.
#' @seealso [DBI::Id()], [DBI::SQL()], [DBI::dbCanConnect()],
#'   [DBI::dbIsReadOnly()], [DBI::dbListObjects()], [DBI::dbQuoteLiteral()],
#'   [DBI::dbUnquoteIdentifier()], [DBI::dbWithTransaction()]
#' @aliases Id SQL dbCanConnect dbIsReadOnly dbListObjects dbQuoteLiteral
#'   dbUnquoteIdentifier dbWithTransaction
NULL
