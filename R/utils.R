# Internal helpers — not exported

#' Quote a string value for safe SQL interpolation
#'
#' Escapes single quotes by doubling them (SQL standard) and wraps in single
#' quotes. Prevents SQL injection for string literals without needing a DB
#' connection.
#'
#' @param x Character scalar.
#' @return Character scalar, e.g. `"'O''Brien'"`.
#' @noRd
.frs_quote_string <- function(x) {
  paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
}


#' Validate a SQL identifier (table or column name)
#'
#' Checks that the identifier matches a safe pattern: word characters, dots
#' (for schema-qualified names), and underscores. Stops with an informative
#' error if validation fails.
#'
#' @param x Character scalar.
#' @param label Character. Name used in error message (e.g. `"table"`).
#' @return `x` invisibly (called for side effect).
#' @noRd
.frs_validate_identifier <- function(x, label = "identifier") {
  if (identical(x, "*")) return(invisible(x))
  if (!grepl("^[A-Za-z_][A-Za-z0-9_.]*$", x)) {
    stop(sprintf("%s contains invalid characters: %s", label, x), call. = FALSE)
  }
  invisible(x)
}


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
      paste0("watershed_group_code = ", .frs_quote_string(watershed_group_code))
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
#' Returns SQL predicates that filter out placeholder streams (999 wscode)
#' and unmapped tributaries (NULL localcode). These are no-ops in network
#' traversal (fwa_upstream/fwa_downstream never return them) but matter
#' for direct table queries (frs_stream_fetch, frs_point_snap KNN).
#'
#' Subsurface flow (edge_type 1410/1425 — underground conduits, culverts)
#' is NOT filtered by default because these are real network connectivity.
#' Use [.frs_snap_guards()] for snap-specific filtering that excludes
#' subsurface segments.
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
    paste0("NOT ", prefix, wscode_col, " <@ '999'")
  )
}


#' Snap-specific filtering guards
#'
#' Like [.frs_stream_guards()] but also excludes subsurface flow
#' (edge_type 1410/1425 — underground conduits). Used by the KNN snap
#' path where snapping to a culvert is not useful.
#'
#' @inheritParams .frs_stream_guards
#' @return Character vector of SQL predicates.
#' @noRd
.frs_snap_guards <- function(alias = "s", wscode_col = "wscode_ltree",
                             localcode_col = "localcode_ltree") {
  c(
    .frs_stream_guards(alias, wscode_col, localcode_col),
    {
      prefix <- if (nzchar(alias)) paste0(alias, ".") else ""
      paste0(prefix, "edge_type NOT IN (1410, 1425)")
    }
  )
}


#' Check if table is the FWA base stream network table
#' @noRd
.is_fwa_stream_table <- function(table) {
  grepl("fwa_stream_networks_sp", tolower(table))
}


#' Transform sf result to a target CRS
#'
#' @param x An `sf` object.
#' @param crs Target CRS (integer EPSG code, character proj4/WKT, or
#'   `sf::st_crs()` object). `NULL` returns `x` unchanged.
#' @return `x`, optionally transformed.
#' @noRd
.frs_transform <- function(x, crs = NULL) {
  if (is.null(crs)) return(x)
  sf::st_transform(x, crs)
}
