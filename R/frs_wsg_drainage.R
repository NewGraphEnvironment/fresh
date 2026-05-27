#' WSG Drainage Closure (FWA Topology)
#'
#' Given a focal set of FWA watershed groups, return the **drainage closure**
#' — every WSG that any focal WSG drains through — ordered downstream-first
#' by outlet ltree depth (`nlevel(outlet) ASC`). Pure FWA topology; no
#' species or bundle knowledge.
#'
#' Sources the FWA WSG outlet table (default `public.wsg_outlet` in fwapg).
#' The closure predicate is `f.outlet <@ w.outlet` — i.e. every WSG whose
#' outlet ltree is an ancestor of (or equal to) any focal WSG's outlet.
#'
#' Order: `depth ASC, wsg ASC` — so the most downstream WSGs come first and
#' ties within a depth are alphabetical. Running per-WSG work in this order
#' persists downstream barriers before upstream WSGs read them, which makes
#' cross-WSG accessibility flags settle correctly within a single pass.
#'
#' @param conn A [DBI::DBIConnection-class] (e.g. from [frs_db_conn()]).
#' @param watershed_group_code Character vector of focal WSG codes (e.g.
#'   `c("BULK", "MORR")`). Must be non-empty and free of `NA`. Codes are
#'   upper-cased internally. Focal codes that don't exist in `table`
#'   trigger a warning and are dropped from the result; if no codes match,
#'   the function errors.
#' @param table Character scalar. Fully-qualified table name holding the
#'   WSG outlet ltree topology. Default `"public.wsg_outlet"`.
#'
#' @return Character vector of WSG codes — focal plus every WSG they flow
#'   through — ordered downstream-first.
#'
#' @family wsg
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # Skeena + Peace focal — returns the 15-WSG drainage closure DS-first
#' frs_wsg_drainage(conn, c("PARS", "BULK"))
#' #> [1] "KISP" "KLUM" "LKEL" "LSKE" "MSKE" "USKE" "BULK" "FINA"
#' #>     "LBTN" "LPCE" "MORR" "PARA" "PCEA" "UPCE" "PARS"
#'
#' DBI::dbDisconnect(conn)
#' }
frs_wsg_drainage <- function(
    conn,
    watershed_group_code,
    table = "public.wsg_outlet"
) {
  stopifnot(
    is.character(watershed_group_code),
    length(watershed_group_code) > 0,
    !anyNA(watershed_group_code),
    all(nzchar(watershed_group_code)),
    is.character(table),
    length(table) == 1L
  )
  .frs_validate_identifier(table, "table")
  focal <- toupper(watershed_group_code)

  focal_lit <- paste(
    DBI::dbQuoteLiteral(conn, focal),
    collapse = ", "
  )
  sql <- sprintf(
    paste0(
      "SELECT DISTINCT w.wsg, nlevel(w.outlet) AS depth\n",
      "FROM %s w\n",
      "JOIN %s f ON f.wsg IN (%s)\n",
      "WHERE f.outlet <@ w.outlet\n",
      "ORDER BY depth ASC, w.wsg ASC"
    ),
    table, table, focal_lit
  )
  res <- DBI::dbGetQuery(conn, sql)
  if (nrow(res) == 0L) {
    stop(
      "No drainage closure found — are the focal WSG codes present in `",
      table, "`?",
      call. = FALSE
    )
  }
  missing <- setdiff(focal, res$wsg)
  if (length(missing) > 0L) {
    warning(
      "Focal WSG code(s) not found in `", table, "` (dropped from closure): ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  res$wsg
}
