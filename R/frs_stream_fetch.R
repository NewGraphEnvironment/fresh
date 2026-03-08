#' Fetch FWA Stream Network Segments
#'
#' Retrieve stream segments from `whse_basemapping.fwa_stream_networks_sp`.
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
#' }
frs_stream_fetch <- function(
    watershed_group_code = NULL,
    blue_line_key = NULL,
    bbox = NULL,
    stream_order_min = NULL,
    limit = NULL,
    ...
) {
  where <- .frs_build_where(
    watershed_group_code = watershed_group_code,
    blue_line_key = blue_line_key,
    bbox = bbox,
    extra = if (!is.null(stream_order_min)) {
      paste0("stream_order >= ", as.integer(stream_order_min))
    }
  )

  sql <- paste0(
    "SELECT * FROM whse_basemapping.fwa_stream_networks_sp",
    where,
    if (!is.null(limit)) paste0(" LIMIT ", as.integer(limit))
  )

  frs_db_query(sql, ...)
}
