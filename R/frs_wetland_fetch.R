#' Fetch FWA Wetlands
#'
#' Retrieve wetland polygons from an FWA wetlands table.
#' Filter by watershed group code, blue line key, bounding box and/or area of
#' interest.
#'
#' Rows come back ordered by `order_by` (the table's unique key by default),
#' so the same database returns the same `sf` on every call. For map layers,
#' `simplify_m` simplifies in the database with
#' `ST_Normalize(ST_SimplifyPreserveTopology(geom, simplify_m))`;
#' `ST_Normalize()` fixes the order of parts, rings and ring start vertices so
#' equal polygons serialise equally. `area_ha` is the stored, unsimplified
#' area. Two databases on different GEOS versions can still simplify a ring
#' differently, so a caller that saves the result should record
#' `postgis_full_version()` with it.
#'
#' @param watershed_group_code Character. Watershed group code (e.g. `"BULK"`).
#'   Default `NULL`.
#' @param blue_line_key Integer. Blue line key for wetlands on a specific stream.
#'   Default `NULL`.
#' @param bbox Numeric vector of length 4 (`xmin`, `ymin`, `xmax`, `ymax`) in
#'   BC Albers (EPSG:3005). Matches on envelope overlap (`&&`), so a wetland
#'   whose envelope touches the box is returned even when the wetland does
#'   not; use `aoi` for exact intersection. Default `NULL`.
#' @param aoi Area of interest. An `sf`/`sfc` polygon (transformed to
#'   EPSG:3005, so it must carry a CRS) filters with `ST_Intersects()`. For
#'   WKT, pass `sf::st_as_sfc(wkt, crs = 3005)`. Also accepts the other forms
#'   of [frs_extract()]'s `aoi`; its character form (watershed group codes) is
#'   an envelope prefilter, so use `watershed_group_code` to select groups.
#'   Default `NULL`.
#' @param simplify_m Numeric. Simplification tolerance in metres, applied in
#'   the database. Drops M coordinates. Default `NULL` (full resolution).
#' @param area_ha_min Numeric. Minimum wetland area in hectares. Default `NULL`.
#' @param table Character. Fully qualified table name. Default
#'   `"whse_basemapping.fwa_wetlands_poly"`.
#' @param cols Character vector of column names to select. Default includes
#'   the most commonly used FWA wetland attributes.
#' @param order_by Character vector. Columns to order rows by. Default
#'   `"waterbody_poly_id"`, the FWA table's unique key; give another table's
#'   unique key (one or more columns) when `table` is changed, or `NULL` for
#'   no `ORDER BY`. With `limit`, the first `limit` rows in this order are
#'   returned.
#' @param limit Integer. Maximum rows to return. Default `NULL` (no limit).
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#'
#' @return An `sf` data frame of wetland polygons.
#'
#' @family fetch
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#' wetlands <- frs_wetland_fetch(conn, watershed_group_code = "BULK")
#' wetlands_big <- frs_wetland_fetch(conn, watershed_group_code = "BULK",
#'   area_ha_min = 5)
#'
#' # Map layer: inside a watershed polygon, simplified to 25 m
#' ws <- frs_watershed_at_measure(conn, 360873822, 208877, simplify_m = 25)
#' wetlands_map <- frs_wetland_fetch(conn, aoi = ws, simplify_m = 25)
#' DBI::dbDisconnect(conn)
#' }
frs_wetland_fetch <- function(
    conn,
    watershed_group_code = NULL,
    blue_line_key = NULL,
    bbox = NULL,
    area_ha_min = NULL,
    table = "whse_basemapping.fwa_wetlands_poly",
    cols = c(
      "waterbody_poly_id", "waterbody_key", "waterbody_type", "area_ha",
      "gnis_name_1", "blue_line_key", "watershed_group_code", "geom"
    ),
    limit = NULL,
    aoi = NULL,
    simplify_m = NULL,
    order_by = "waterbody_poly_id"
) {
  .frs_validate_identifier(table, "table")
  for (col in cols) .frs_validate_identifier(col, "column")

  where <- .frs_build_where(
    watershed_group_code = watershed_group_code,
    blue_line_key = blue_line_key,
    bbox = bbox,
    aoi = aoi,
    conn = conn,
    extra = if (!is.null(area_ha_min)) {
      paste0("area_ha >= ", .frs_sql_exact(area_ha_min, "area_ha_min"))
    }
  )

  sql <- paste0(
    "SELECT ", .frs_geom_select(cols, simplify_m),
    " FROM ", table,
    where,
    .frs_order_by(order_by),
    if (!is.null(limit)) paste0(" LIMIT ", as.integer(limit))
  )

  frs_db_query(conn, sql)
}
