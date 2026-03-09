#' Fetch FWA Stream Network Segments
#'
#' Retrieve stream segments from a stream network table.
#' Filter by watershed group code, blue line key, and/or bounding box.
#'
#' @param watershed_group_code Character. Watershed group code (e.g. `"BULK"`).
#'   Default `NULL`.
#' @param blue_line_key Integer. Blue line key for a specific stream. Default
#'   `NULL`.
#' @param bbox Numeric vector of length 4 (`xmin`, `ymin`, `xmax`, `ymax`) in
#'   BC Albers (EPSG:3005). Default `NULL`.
#' @param stream_order_min Integer. Minimum Strahler stream order to return.
#'   Default `NULL` (all orders).
#' @param table Character. Fully qualified table name. Default
#'   `"whse_basemapping.fwa_stream_networks_sp"`.
#' @param cols Character vector of column names to select. Default includes
#'   the most commonly used FWA stream attributes.
#' @param include_all Logical. If `TRUE`, include placeholder streams (999
#'   wscode) and unmapped tributaries (NULL localcode). Default `FALSE` filters
#'   these out. Only applied when querying the FWA base table.
#' @param limit Integer. Maximum rows to return. Default `NULL` (no limit).
#' @param ... Additional arguments passed to [frs_db_conn()].
#'
#' @return An `sf` data frame of stream segments.
#'
#' @family fetch
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # All streams in the Bulkley watershed group
#' streams <- frs_stream_fetch(watershed_group_code = "BULK")
#'
#' # Streams with order >= 4
#' streams <- frs_stream_fetch(watershed_group_code = "BULK", stream_order_min = 4)
#'
#' # Custom columns and table
#' streams <- frs_stream_fetch(
#'   watershed_group_code = "BULK",
#'   cols = c("blue_line_key", "gnis_name", "stream_order", "geom")
#' )
#' }
frs_stream_fetch <- function(
    watershed_group_code = NULL,
    blue_line_key = NULL,
    bbox = NULL,
    stream_order_min = NULL,
    table = "whse_basemapping.fwa_stream_networks_sp",
    cols = c(
      "linear_feature_id", "blue_line_key", "waterbody_key", "edge_type",
      "gnis_name", "stream_order", "stream_magnitude", "gradient",
      "downstream_route_measure", "upstream_route_measure", "length_metre",
      "watershed_group_code", "wscode_ltree", "localcode_ltree", "geom"
    ),
    include_all = FALSE,
    limit = NULL,
    ...
) {
  extra_guards <- character(0)
  if (!include_all && .is_fwa_stream_table(table)) {
    extra_guards <- .frs_stream_guards(alias = "")
  }
  if (!is.null(stream_order_min)) {
    extra_guards <- c(extra_guards, paste0("stream_order >= ", as.integer(stream_order_min)))
  }

  where <- .frs_build_where(
    watershed_group_code = watershed_group_code,
    blue_line_key = blue_line_key,
    bbox = bbox,
    extra = if (length(extra_guards) > 0) extra_guards
  )

  sql <- paste0(
    "SELECT ", paste(cols, collapse = ", "),
    " FROM ", table,
    where,
    if (!is.null(limit)) paste0(" LIMIT ", as.integer(limit))
  )

  frs_db_query(sql, ...)
}
