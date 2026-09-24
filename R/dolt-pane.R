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

# shiny, miniUI and DT are Suggests: this is one optional entry point in a
# package whose job is to be a DBI backend, and most users never open it.
DOLTLITE_PANE_PKGS <- c("shiny", "miniUI", "DT")

doltlite_require_shiny <- function() {
  missing <- DOLTLITE_PANE_PKGS[
    !vapply(DOLTLITE_PANE_PKGS, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing)) {
    listed <- if (length(missing) == 1L) {
      missing
    } else {
      paste(paste(missing[-length(missing)], collapse = ", "),
            "and", missing[[length(missing)]])
    }
    stop(sprintf(
      "dolt_pane() needs %s. Install with:\n  install.packages(c(%s))",
      listed, paste(sprintf('"%s"', missing), collapse = ", ")
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

# Shared DT options. A gadget pane is short and narrow, so the table has to
# scroll horizontally rather than wrap, and the usual DataTables chrome
# (length menu, "Showing 1 to n of m") costs more room than it earns.
doltlite_pane_dt <- function(df, page_length = 8L, ...) {
  DT::datatable(
    df,
    rownames = FALSE,
    class = "compact stripe hover nowrap",
    options = list(
      scrollX = TRUE,
      pageLength = page_length,
      lengthChange = FALSE,
      searching = FALSE,
      info = FALSE,
      dom = "tp"
    ),
    ...
  )
}

# A row-level diff arrives as from_/to_ column pairs plus commit metadata.
# The pairs are the point of the view, so the commit columns are dropped --
# both endpoints are already fixed by the HEAD -> WORKING heading, and they
# are wide enough to push the actual values off screen.
doltlite_pane_diff_table <- function(d) {
  if (is.null(d) || nrow(d) == 0L) {
    return(doltlite_pane_dt(data.frame(`No differences` = character(),
                                       check.names = FALSE)))
  }
  drop <- c("to_commit", "from_commit", "to_commit_date", "from_commit_date")
  keep <- setdiff(names(d), drop)
  d <- d[, keep, drop = FALSE]

  # Lead with diff_type: it is what you scan for.
  if ("diff_type" %in% names(d)) {
    d <- d[, c("diff_type", setdiff(names(d), "diff_type")), drop = FALSE]
  }

  tbl <- doltlite_pane_dt(d)
  if ("diff_type" %in% names(d)) {
    tbl <- DT::formatStyle(
      tbl, "diff_type",
      color = DT::styleEqual(
        c("added", "modified", "removed"),
        c("#2f855a", "#b7791f", "#c53030")
      ),
      fontWeight = "bold"
    )
  }
  tbl
}

doltlite_pane_branches_table <- function(br, current = NULL) {
  if (is.null(br) || nrow(br) == 0L) {
    return(doltlite_pane_dt(data.frame(`No branches` = character(),
                                       check.names = FALSE)))
  }
  df <- data.frame(
    branch = ifelse(br$name == current, paste0(br$name, "  *"), br$name),
    last_commit = br$latest_commit_message,
    when = as.character(br$latest_commit_date),
    who = br$latest_committer,
    stringsAsFactors = FALSE
  )
  doltlite_pane_dt(df)
}

# The conflict relation puts base, ours and theirs side by side for every
# conflicted row. That is exactly the shape you want to read before choosing a
# side, so it is shown as-is apart from the internal join key.
doltlite_pane_conflicts_table <- function(cf) {
  if (is.null(cf) || nrow(cf) == 0L) {
    return(doltlite_pane_dt(data.frame(`No conflicts` = character(),
                                       check.names = FALSE)))
  }
  cf <- cf[, setdiff(names(cf), c("from_root_ish", "dolt_conflict_id")),
           drop = FALSE]
  tbl <- doltlite_pane_dt(cf, page_length = 6L)
  ours <- grep("^our_", names(cf), value = TRUE)
  theirs <- grep("^their_", names(cf), value = TRUE)
  if (length(ours)) {
    tbl <- DT::formatStyle(tbl, ours, backgroundColor = "#f0f7ff")
  }
  if (length(theirs)) {
    tbl <- DT::formatStyle(tbl, theirs, backgroundColor = "#fff7ed")
  }
  tbl
}

# Run a merge and say what state it left behind.
#
# Kept out of the reactives because the sequencing is the fiddly part, and it
# is driven entirely by measured behaviour:
#
#   * A conflicting merge in autocommit is rolled back whole, so there is
#     nothing left to resolve. The merge therefore has to run inside a
#     transaction for conflicts to be inspectable at all.
#   * A *clean* merge ends the transaction itself, so committing afterwards
#     unconditionally would raise "no transaction is open".
#   * A merge refused for a dirty working set leaves the transaction open, so
#     the error path has to roll back rather than assume it was unwound.
#
# Returns state: "blocked" (refused before starting), "failed" (the merge
# errored), "conflicted" (transaction still open, conflicts to resolve), or
# "merged" (done).
doltlite_pane_do_merge <- function(con, source) {
  if (doltlite_in_transaction(con)) {
    return(list(state = "blocked", message = paste(
      "A SQL transaction is already open on this connection.",
      "Commit or roll it back in the console first."
    )))
  }
  if (nrow(doltlite_pane_status(con)) > 0L) {
    return(list(state = "blocked", message = paste(
      "The working set has uncommitted changes.",
      "Commit them on the Changes tab before merging."
    )))
  }

  DBI::dbBegin(con)
  res <- tryCatch(dolt_merge(con, source), error = function(e) e)

  if (inherits(res, "error")) {
    if (doltlite_in_transaction(con)) {
      try(DBI::dbRollback(con), silent = TRUE)
    }
    return(list(state = "failed", message = conditionMessage(res)))
  }

  conflicted <- tryCatch(nrow(dolt_conflicts(con)) > 0L,
                         error = function(e) FALSE)
  if (conflicted) {
    return(list(state = "conflicted", message = paste(res, collapse = " ")))
  }

  if (doltlite_in_transaction(con)) {
    try(DBI::dbCommit(con), silent = TRUE)
  }
  list(state = "merged", message = paste(res, collapse = " "))
}

# Detail rows for the conflicted tables.
#
# dolt_conflicts() gives a per-table count; the base/ours/theirs columns live
# in a per-table relation whose shape follows that table, so two conflicted
# tables cannot be stacked into one frame. With a single table its detail is
# shown, which is the common case and the useful one; with several, the
# per-table summary is shown instead rather than inventing a merged shape.
doltlite_pane_conflict_detail <- function(con, summary = NULL) {
  if (is.null(summary)) summary <- dolt_conflicts(con)
  if (is.null(summary) || nrow(summary) == 0L) return(NULL)
  tables <- as.character(summary[[1L]])
  if (length(tables) != 1L) return(summary)
  dolt_conflicts_table(con, tables[[1L]])
}

# Abandon a conflicted merge. Rolling back is what undoes it: conflicts
# disappear, the rows return to their pre-merge values and is_merging clears.
doltlite_pane_abort_merge <- function(con) {
  if (doltlite_in_transaction(con)) {
    try(DBI::dbRollback(con), silent = TRUE)
  }
  invisible(TRUE)
}

doltlite_pane_log_table <- function(lg) {
  if (is.null(lg) || nrow(lg) == 0L) {
    return(doltlite_pane_dt(data.frame(`No commits yet` = character(),
                                       check.names = FALSE)))
  }
  doltlite_pane_dt(
    data.frame(
      commit = substr(lg$commit_hash, 1L, 8L),
      date = as.character(lg$date),
      committer = lg$committer,
      message = lg$message,
      stringsAsFactors = FALSE
    ),
    page_length = 12L
  )
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
#' @section Merging:
#' The Branches tab lists the branches, creates and switches between them, and
#' merges one into the branch this connection is on.
#'
#' Merges run inside a transaction, because they have to: DoltLite rolls a
#' conflicting merge back whole in autocommit mode, so there would be nothing
#' left to inspect or resolve. When a merge conflicts, the gadget keeps that
#' transaction open and shows base, ours and theirs side by side, with buttons
#' to keep one side, commit the result, or abort. Aborting rolls back, which
#' restores the rows and clears the merge.
#'
#' Two consequences worth knowing. A conflicted merge means an open
#' transaction on your connection, so finish or abort it before going back to
#' the console; closing the gadget rolls it back rather than stranding it. And
#' a merge is refused while the working set is dirty, since DoltLite requires
#' a clean one -- commit on the Changes tab first.
#'
#' Remotes are not wrapped here; use [dolt_push()] and [dolt_pull()].
#'
#' @seealso [dolt_status()], [dolt_table_diff()], [dolt_log()],
#'   [dolt_merge()], [dolt_conflicts()]
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
        # fluidRow rather than fillRow: a fill container expands to the height
        # of the panel and pushes whatever follows it out of view, which hid
        # the commit box entirely.
        miniUI::miniContentPanel(
          scrollable = TRUE,
          shiny::fluidRow(
            shiny::column(
              4,
              shiny::div(
                shiny::strong("Branch: "),
                shiny::textOutput("branch", inline = TRUE),
                shiny::actionButton("refresh", "Refresh", class = "btn-sm",
                                    style = "margin-left: 8px;")
              ),
              shiny::hr(),
              shiny::uiOutput("table_picker")
            ),
            shiny::column(
              8,
              shiny::strong("Diff (HEAD \u2192 WORKING)"),
              DT::DTOutput("diff")
            )
          ),
          shiny::hr(),
          shiny::fluidRow(
            shiny::column(
              8,
              shiny::textInput("msg", NULL, placeholder = "Commit message",
                               width = "100%")
            ),
            shiny::column(
              4,
              shiny::actionButton("commit", "Stage everything and commit",
                                  class = "btn-primary", width = "100%")
            )
          ),
          shiny::textOutput("commit_msg")
        )
      ),
      miniUI::miniTabPanel(
        "Branches", icon = shiny::icon("code-branch"),
        miniUI::miniContentPanel(
          scrollable = TRUE,
          shiny::fluidRow(
            shiny::column(
              7,
              shiny::strong("Branches "),
              shiny::span("(* is the one this connection is on)",
                          style = "color:#666; font-size:90%;"),
              DT::DTOutput("branches")
            ),
            shiny::column(
              5,
              shiny::textInput("new_branch", NULL,
                               placeholder = "New branch name"),
              shiny::actionButton("create", "Create and switch to it",
                                  width = "100%"),
              shiny::hr(),
              shiny::uiOutput("branch_picker"),
              shiny::actionButton("checkout", "Switch to selected",
                                  width = "100%"),
              shiny::br(), shiny::br(),
              shiny::actionButton("merge", "Merge selected into current",
                                  class = "btn-primary", width = "100%")
            )
          ),
          shiny::textOutput("branch_msg"),
          shiny::uiOutput("conflict_panel")
        )
      ),
      miniUI::miniTabPanel(
        "History", icon = shiny::icon("clock"),
        miniUI::miniContentPanel(DT::DTOutput("log"))
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

    output$diff <- DT::renderDT({
      st <- status()
      # Render the empty state rather than req()-ing out, so a clean working
      # set says "No differences" instead of leaving the heading over a void.
      if (nrow(st) == 0L) return(doltlite_pane_diff_table(NULL))
      shiny::req(input$table)
      d <- tryCatch(
        dolt_table_diff(con, input$table, from = "HEAD", to = "WORKING"),
        error = function(e) data.frame(error = conditionMessage(e))
      )
      doltlite_pane_diff_table(d)
    })

    output$log <- DT::renderDT({
      tick()
      doltlite_pane_log_table(tryCatch(dolt_log(con), error = function(e) NULL))
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

    ## Branches -------------------------------------------------------------

    # Non-NULL while a conflicted merge is holding a transaction open.
    merging <- shiny::reactiveVal(NULL)

    branches <- shiny::reactive({
      tick()
      tryCatch(dolt_branches(con), error = function(e) NULL)
    })

    output$branches <- DT::renderDT({
      doltlite_pane_branches_table(
        branches(), tryCatch(active_branch(con), error = function(e) NULL)
      )
    })

    output$branch_picker <- shiny::renderUI({
      br <- branches()
      cur <- tryCatch(active_branch(con), error = function(e) NULL)
      others <- setdiff(if (is.null(br)) character() else br$name, cur)
      if (length(others) == 0L) {
        return(shiny::em("No other branches yet."))
      }
      shiny::selectInput("other_branch", "Other branch", choices = others)
    })

    say <- function(txt) output$branch_msg <- shiny::renderText(txt)

    shiny::observeEvent(input$create, {
      nm <- trimws(input$new_branch %||% "")
      if (!nzchar(nm)) {
        say("Enter a branch name first.")
        return()
      }
      res <- tryCatch({
        dolt_checkout(con, nm, create = TRUE)
        sprintf("Created and switched to '%s'.", nm)
      }, error = function(e) paste("failed:", conditionMessage(e)))
      shiny::updateTextInput(session, "new_branch", value = "")
      say(res)
      refresh()
    })

    shiny::observeEvent(input$checkout, {
      shiny::req(input$other_branch)
      res <- tryCatch({
        dolt_checkout(con, input$other_branch)
        sprintf("Switched to '%s'.", input$other_branch)
      }, error = function(e) paste("failed:", conditionMessage(e)))
      say(res)
      refresh()
    })

    shiny::observeEvent(input$merge, {
      shiny::req(input$other_branch)
      if (!is.null(merging())) {
        say("Finish or abort the merge in progress first.")
        return()
      }
      res <- doltlite_pane_do_merge(con, input$other_branch)
      if (identical(res$state, "conflicted")) merging(input$other_branch)
      say(res$message)
      refresh()
    })

    # The conflict panel only exists while a merge is open, so there is no way
    # to reach resolve or abort except from a genuinely conflicted state.
    output$conflict_panel <- shiny::renderUI({
      src <- merging()
      if (is.null(src)) return(NULL)
      shiny::div(
        shiny::hr(),
        shiny::h4(sprintf("Conflicts merging '%s'", src)),
        shiny::p(shiny::strong("This merge is holding a transaction open."),
                 " Resolve and commit, or abort, before using the console."),
        DT::DTOutput("conflicts"),
        shiny::br(),
        shiny::fluidRow(
          shiny::column(3, shiny::actionButton(
            "resolve_ours", "Keep ours", width = "100%")),
          shiny::column(3, shiny::actionButton(
            "resolve_theirs", "Keep theirs", width = "100%")),
          shiny::column(3, shiny::actionButton(
            "commit_merge", "Commit merge", class = "btn-primary",
            width = "100%")),
          shiny::column(3, shiny::actionButton(
            "abort_merge", "Abort", class = "btn-danger", width = "100%"))
        )
      )
    })

    output$conflicts <- DT::renderDT({
      tick()
      shiny::req(merging())
      summary <- tryCatch(dolt_conflicts(con), error = function(e) NULL)
      if (is.null(summary) || nrow(summary) == 0L) {
        return(doltlite_pane_conflicts_table(NULL))
      }
      detail <- tryCatch(doltlite_pane_conflict_detail(con, summary),
                         error = function(e) NULL)
      doltlite_pane_conflicts_table(detail)
    })

    resolve_with <- function(side) {
      res <- tryCatch({
        dolt_conflicts_resolve(con, side)
        sprintf("Resolved using %s. Commit the merge to finish.", side)
      }, error = function(e) paste("failed:", conditionMessage(e)))
      say(res)
      refresh()
    }
    shiny::observeEvent(input$resolve_ours, resolve_with("ours"))
    shiny::observeEvent(input$resolve_theirs, resolve_with("theirs"))

    shiny::observeEvent(input$commit_merge, {
      src <- merging()
      shiny::req(src)
      left <- tryCatch(nrow(dolt_conflicts(con)), error = function(e) 0L)
      if (left > 0L) {
        say(sprintf("%d table(s) still conflicted. Resolve them first.", left))
        return()
      }
      res <- tryCatch({
        dolt_commit(con, sprintf("Merge branch '%s'", src))
        merging(NULL)
        sprintf("Merged '%s'.", src)
      }, error = function(e) paste("failed:", conditionMessage(e)))
      say(res)
      refresh()
    })

    shiny::observeEvent(input$abort_merge, {
      doltlite_pane_abort_merge(con)
      merging(NULL)
      say("Merge aborted; nothing was changed.")
      refresh()
    })

    # Closing the window must not strand an open transaction on the caller's
    # connection, so an unfinished merge is rolled back on the way out.
    session$onSessionEnded(function() {
      if (!is.null(shiny::isolate(merging()))) doltlite_pane_abort_merge(con)
    })

    shiny::observeEvent(input$done, shiny::stopApp())
    shiny::observeEvent(input$cancel, shiny::stopApp())
  }
}
