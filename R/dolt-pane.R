# A Git-pane-style gadget for a DoltLite connection.
#
# This deliberately runs in the caller's R process, on the caller's connection,
# rather than as a background job watching the file. A second connection is not
# equivalent: branches are per connection, so a background pane would report
# its own branch rather than yours and could commit onto the wrong one; it is
# blind to anything inside an open transaction; and it cannot write at all
# while you hold one. Being an on-demand gadget is the honest shape for this.

# Find the one open DoltLite connection in `env`.
#
# Kept separate from the gadget so it can be tested without Shiny. Returns the
# connection, or throws describing what it found -- ambiguity is an error
# rather than a guess, because picking the wrong connection here means acting
# on the wrong database.
doltlite_find_connection <- function(env = globalenv()) {
  nms <- ls(env)
  hits <- character()
  for (nm in nms) {
    obj <- tryCatch(get(nm, envir = env), error = function(e) NULL)
    if (methods::is(obj, "DoltliteConnection") && dbIsValid(obj)) {
      hits <- c(hits, nm)
    }
  }
  if (length(hits) == 0L) {
    stop("no open DoltliteConnection found; pass one as `con`", call. = FALSE)
  }
  if (length(hits) > 1L) {
    stop(sprintf(
      "found %d open connections (%s); pass the one you want as `con`",
      length(hits), paste(hits, collapse = ", ")
    ), call. = FALSE)
  }
  get(hits[[1L]], envir = env)
}

# Shiny and miniUI are Suggests: this is one optional entry point in a package
# whose job is to be a DBI backend, and most users never open it.
doltlite_require_shiny <- function() {
  missing <- c("shiny", "miniUI")[
    !vapply(c("shiny", "miniUI"), requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing)) {
    stop(sprintf(
      "dolt_pane() needs %s. Install with:\n  install.packages(c(%s))",
      paste(missing, collapse = " and "),
      paste(sprintf('"%s"', missing), collapse = ", ")
    ), call. = FALSE)
  }
  invisible(TRUE)
}

# Tables with uncommitted changes, newest listing first. Returns a zero-row
# frame rather than NULL when the working set is clean, so callers can treat
# the shape uniformly.
doltlite_pane_status <- function(con) {
  st <- dolt_status(con)
  if (is.null(st) || nrow(st) == 0L) {
    return(data.frame(table_name = character(), staged = integer(),
                      status = character(), stringsAsFactors = FALSE))
  }
  st
}

#' A Git-pane-style gadget for a DoltLite connection
#'
#' Opens a Shiny gadget showing what a version-control pane should show: the
#' tables with uncommitted changes, the row-level diff for whichever you
#' select, the commit history, and a commit box.
#'
#' It runs in your R session, on the connection you give it. That is a
#' deliberate constraint rather than a simplification: branches in DoltLite are
#' per connection, so a pane holding its own connection would display its own
#' branch rather than yours, and committing from it could land your work on a
#' branch you are not on. It would also see nothing inside an open transaction,
#' and could not write while you held one. Running in-process avoids all three,
#' at the cost of blocking the console while the gadget is open.
#'
#' @param con a `DoltliteConnection`. If omitted, and exactly one open
#'   connection exists in `env`, that one is used; ambiguity is an error.
#' @param env environment to search when `con` is omitted.
#' @param viewer a Shiny viewer, passed to [shiny::runGadget()]. Defaults to
#'   RStudio's pane viewer when available.
#'
#' @return Invisibly, the connection it acted on.
#'
#' @section Committing:
#' The Commit button refuses while a SQL transaction is open. This is not
#' caution for its own sake: `dolt_commit()` ends the enclosing transaction, so
#' committing from the gadget mid-`dbBegin()` would silently end a transaction
#' the console still believes is running. Commit or roll back first.
#'
#' `Stage everything and commit` runs `dolt_add("-A")`, which sweeps up every
#' change in the working set, not only the table you are looking at.
#'
#' @seealso [dolt_status()], [dolt_table_diff()], [dolt_log()]
#' @export
#' @examples
#' \dontrun{
#' con <- DBI::dbConnect(doltliter::Doltlite(), "mydata.db")
#' dolt_pane(con)
#' }
dolt_pane <- function(con = NULL, env = parent.frame(), viewer = NULL) {
  doltlite_require_shiny()
  if (is.null(con)) con <- doltlite_find_connection(env)
  dolt_require_conn(con)
  dolt_require_versioned(con, "dolt_pane")

  if (is.null(viewer)) {
    viewer <- if (requireNamespace("rstudioapi", quietly = TRUE) &&
                  rstudioapi::isAvailable()) {
      shiny::paneViewer()
    } else {
      shiny::browserViewer()
    }
  }

  shiny::runGadget(
    doltlite_pane_ui(con),
    doltlite_pane_server(con),
    viewer = viewer
  )
  invisible(con)
}

#' @rdname dolt_pane
#' @export
dolt_pane_addin <- function() dolt_pane(env = globalenv())

doltlite_pane_ui <- function(con) {
  dbname <- tryCatch(dbGetInfo(con)$dbname, error = function(e) "?")

  miniUI::miniPage(
    miniUI::gadgetTitleBar(
      sprintf("doltliter \u2014 %s", basename(dbname)),
      right = miniUI::miniTitleBarButton("done", "Close", primary = TRUE)
    ),
    miniUI::miniTabstripPanel(
      miniUI::miniTabPanel(
        "Changes", icon = shiny::icon("table"),
        miniUI::miniContentPanel(
          shiny::fillRow(
            flex = c(1, 2),
            shiny::div(
              shiny::strong("Branch: "),
              shiny::textOutput("branch", inline = TRUE),
              shiny::actionButton("refresh", "Refresh", class = "btn-sm"),
              shiny::hr(),
              shiny::uiOutput("table_picker")
            ),
            shiny::div(
              shiny::strong("Diff (HEAD \u2192 WORKING)"),
              shiny::tableOutput("diff")
            )
          ),
          shiny::hr(),
          shiny::textInput("msg", NULL, placeholder = "Commit message",
                           width = "100%"),
          shiny::actionButton("commit", "Stage everything and commit",
                              class = "btn-primary"),
          shiny::textOutput("commit_msg")
        )
      ),
      miniUI::miniTabPanel(
        "History", icon = shiny::icon("clock"),
        miniUI::miniContentPanel(shiny::tableOutput("log"))
      )
    )
  )
}

doltlite_pane_server <- function(con) {
  function(input, output, session) {
    # Everything reads through this, so one bump refreshes the whole gadget.
    tick <- shiny::reactiveVal(0)
    refresh <- function() tick(shiny::isolate(tick()) + 1)

    status <- shiny::reactive({
      tick()
      doltlite_pane_status(con)
    })

    output$branch <- shiny::renderText({
      tick()
      tryCatch(active_branch(con), error = function(e) "?")
    })

    output$table_picker <- shiny::renderUI({
      st <- status()
      if (nrow(st) == 0L) {
        return(shiny::em("Working set is clean."))
      }
      shiny::radioButtons(
        "table", sprintf("Changed (%d)", nrow(st)),
        choiceNames = sprintf("%s \u2014 %s", st$table_name, st$status),
        choiceValues = st$table_name
      )
    })

    output$diff <- shiny::renderTable({
      st <- status()
      shiny::req(nrow(st) > 0L, input$table)
      d <- tryCatch(
        dolt_table_diff(con, input$table, from = "HEAD", to = "WORKING"),
        error = function(e) data.frame(error = conditionMessage(e))
      )
      # A wide diff of a big table is not what this view is for; show a window
      # and let the console have the rest. Indexed rather than utils::head()
      # so the package needs no dependency on utils for one truncation.
      if (nrow(d) > 200L) d[seq_len(200L), , drop = FALSE] else d
    })

    output$log <- shiny::renderTable({
      tick()
      lg <- tryCatch(dolt_log(con), error = function(e) NULL)
      if (is.null(lg) || nrow(lg) == 0L) return(NULL)
      data.frame(
        commit = substr(lg$commit_hash, 1L, 8L),
        date = as.character(lg$date),
        committer = lg$committer,
        message = lg$message,
        stringsAsFactors = FALSE
      )
    })

    shiny::observeEvent(input$refresh, refresh())

    shiny::observeEvent(input$commit, {
      msg <- trimws(input$msg %||% "")
      if (!nzchar(msg)) {
        output$commit_msg <- shiny::renderText("Enter a commit message first.")
        return()
      }
      # dolt_commit() ends the enclosing SQL transaction. Doing that from here
      # would leave the console holding a transaction that no longer exists.
      if (doltlite_in_transaction(con)) {
        output$commit_msg <- shiny::renderText(
          paste("A SQL transaction is open. dolt_commit() would end it,",
                "so commit or roll back in the console first.")
        )
        return()
      }
      res <- tryCatch({
        dolt_add(con)
        dolt_commit(con, msg)
        "committed"
      }, error = function(e) paste("failed:", conditionMessage(e)))
      shiny::updateTextInput(session, "msg", value = "")
      output$commit_msg <- shiny::renderText(res)
      refresh()
    })

    shiny::observeEvent(input$done, shiny::stopApp())
    shiny::observeEvent(input$cancel, shiny::stopApp())
  }
}
