# Internal helpers — not exported

#' Build a SQL WHERE clause from common filter parameters
#'
#' @param watershed_group_code Character or NULL.
#' @param blue_line_key Integer or NULL.
#' @param bbox Numeric length-4 or NULL (xmin, ymin, xmax, ymax in EPSG:3005).
#' @param extra Character vector of additional SQL predicates.
#'
#' @return Character string starting with " WHERE ..." or empty string.
#' @noRd
.frs_build_where <- function(
    watershed_group_code = NULL,
    blue_line_key = NULL,
    bbox = NULL,
    extra = NULL
) {
  clauses <- character(0)

  if (!is.null(watershed_group_code)) {
    clauses <- c(
      clauses,
      paste0("watershed_group_code = '", watershed_group_code, "'")
    )
  }

  if (!is.null(blue_line_key)) {
    clauses <- c(clauses, paste0("blue_line_key = ", as.integer(blue_line_key)))
  }

  if (!is.null(bbox)) {
    stopifnot(length(bbox) == 4)
    clauses <- c(
      clauses,
      sprintf(
        "geom && ST_MakeEnvelope(%s, %s, %s, %s, 3005)",
        bbox[1], bbox[2], bbox[3], bbox[4]
      )
    )
  }

  if (!is.null(extra)) {
    clauses <- c(clauses, extra)
  }

  if (length(clauses) == 0) return("")

  paste0(" WHERE ", paste(clauses, collapse = " AND "))
}


#' Stream filtering guards to exclude invalid FWA segments
#'
#' Returns SQL predicates that filter out placeholder streams (999 wscode),
#' subsurface flow (edge_type 1410/1425), and unmapped tributaries (NULL
#' localcode). These guards match the bcfishpass universal filter pattern.
#'
#' @param alias Character. Table alias prefix. Default `"s"`.
#' @param wscode_col Character. Watershed code column name. Default
#'   `"wscode_ltree"`.
#' @param localcode_col Character. Local code column name. Default
#'   `"localcode_ltree"`.
#' @return Character vector of SQL predicates.
#' @noRd
.frs_stream_guards <- function(alias = "s", wscode_col = "wscode_ltree",
                               localcode_col = "localcode_ltree") {
  prefix <- if (nzchar(alias)) paste0(alias, ".") else ""
  c(
    paste0(prefix, localcode_col, " IS NOT NULL"),
    paste0("NOT ", prefix, wscode_col, " <@ '999'"),
    paste0(prefix, "edge_type NOT IN (1410, 1425)")
  )
}


#' Check if table is the FWA base stream network table
#' @noRd
.is_fwa_stream_table <- function(table) {
  grepl("fwa_stream_networks_sp", tolower(table))
}
