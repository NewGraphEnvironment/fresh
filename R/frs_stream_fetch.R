#' Fetch FWA Stream Network Segments
#'
#' Retrieve stream segments from a stream network table.
#' Filter by watershed group code, blue line key, bounding box and/or area of
#' interest.
#'
#' Rows come back ordered by `order_by` (the table's unique key by default),
#' so the same database returns the same `sf` on every call. For map layers,
#' `simplify_m` simplifies in the database with
#' `ST_SimplifyPreserveTopology(geom, simplify_m)`. Unlike the polygon
#' fetchers it is not wrapped in `ST_Normalize()`, which would reverse any
#' line whose first vertex sorts after its last, so segments keep their
#' digitized (downstream to upstream) direction. `length_metre` is the stored,
#' unsimplified length. Two databases on different GEOS versions can still
#' simplify a line differently, so a caller that saves the result should
#' record `postgis_full_version()` with it.
#'
#' @param watershed_group_code Character. Watershed group code (e.g. `"BULK"`).
#'   Default `NULL`.
#' @param blue_line_key Integer. Blue line key for a specific stream. Default
#'   `NULL`.
#' @param bbox Numeric vector of length 4 (`xmin`, `ymin`, `xmax`, `ymax`) in
#'   BC Albers (EPSG:3005). Matches on envelope overlap (`&&`), so a segment
#'   whose envelope touches the box is returned even when the segment does
#'   not; use `aoi` for exact intersection. Default `NULL`.
#' @param aoi Area of interest. An `sf`/`sfc` polygon (transformed to
#'   EPSG:3005, so it must carry a CRS) filters with `ST_Intersects()`. For
#'   WKT, pass `sf::st_as_sfc(wkt, crs = 3005)`. Also accepts the other forms
#'   of [frs_extract()]'s `aoi`; its character form (watershed group codes) is
#'   an envelope prefilter, so use `watershed_group_code` to select groups.
#'   Default `NULL`.
#' @param simplify_m Numeric. Simplification tolerance in metres, applied in
#'   the database. Drops M coordinates. Default `NULL` (full resolution).
#' @param stream_order_min Integer. Minimum Strahler stream order to return.
#'   Default `NULL` (all orders).
#' @param table Character. Fully qualified table name. Default
#'   `"whse_basemapping.fwa_stream_networks_sp"`.
#' @param cols Character vector of column names to select. Default includes
#'   the most commonly used FWA stream attributes.
#' @param include_all Logical. If `TRUE`, include placeholder streams (999
#'   wscode) and unmapped tributaries (NULL localcode). Default `FALSE` filters
#'   these out. Only applied when querying the FWA base table.
#' @param order_by Character vector. Columns to order rows by. Default
#'   `"linear_feature_id"`, the FWA table's unique key; give another table's
#'   unique key (one or more columns) when `table` is changed, or `NULL` for
#'   no `ORDER BY`. With `limit`, the first `limit` rows in this order are
#'   returned.
#' @param limit Integer. Maximum rows to return. Default `NULL` (no limit).
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#'
#' @return An `sf` data frame of stream segments.
#'
#' @family fetch
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # All streams in the Bulkley watershed group
#' streams <- frs_stream_fetch(conn, watershed_group_code = "BULK")
#'
#' # Streams with order >= 4
#' streams <- frs_stream_fetch(conn, watershed_group_code = "BULK",
#'   stream_order_min = 4)
#'
#' # Map layer: inside a watershed polygon, simplified to 25 m
#' ws <- frs_watershed_at_measure(conn, 360873822, 208877, simplify_m = 25)
#' streams_map <- frs_stream_fetch(conn, aoi = ws, stream_order_min = 3,
#'   simplify_m = 25)
#' DBI::dbDisconnect(conn)
#' }
frs_stream_fetch <- function(
    conn,
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
    aoi = NULL,
    simplify_m = NULL,
    order_by = "linear_feature_id"
) {
  .frs_validate_identifier(table, "table")
  for (col in cols) .frs_validate_identifier(col, "column")

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
    aoi = aoi,
    conn = conn,
    extra = if (length(extra_guards) > 0) extra_guards
  )

  sql <- paste0(
    "SELECT ", .frs_geom_select(cols, simplify_m, normalize = FALSE),
    " FROM ", table,
    where,
    .frs_order_by(order_by),
    if (!is.null(limit)) paste0(" LIMIT ", as.integer(limit))
  )

  frs_db_query(conn, sql)
}
