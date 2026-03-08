#' Fetch FWA Lakes
#'
#' Retrieve lake polygons from an FWA lakes table.
#' Filter by watershed group code, blue line key, and/or bounding box.
#'
#' @param watershed_group_code Character. Watershed group code (e.g. `"BULK"`).
#'   Default `NULL`.
#' @param blue_line_key Integer. Blue line key for lakes on a specific stream.
#'   Default `NULL`.
#' @param bbox Numeric vector of length 4 (`xmin`, `ymin`, `xmax`, `ymax`) in
#'   BC Albers (EPSG:3005). Default `NULL`.
#' @param area_ha_min Numeric. Minimum lake area in hectares. Default `NULL`.
#' @param table Character. Fully qualified table name. Default
#'   `"whse_basemapping.fwa_lakes_poly"`.
#' @param cols Character vector of column names to select. Default includes
#'   the most commonly used FWA lake attributes.
#' @param limit Integer. Maximum rows to return. Default `NULL` (no limit).
#' @param ... Additional arguments passed to [frs_db_conn()].
#'
#' @return An `sf` data frame of lake polygons.
#'
#' @family fetch
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # All lakes in the Bulkley watershed group
#' lakes <- frs_lake_fetch(watershed_group_code = "BULK")
#'
#' # Lakes larger than 10 ha
#' lakes <- frs_lake_fetch(watershed_group_code = "BULK", area_ha_min = 10)
#' }
frs_lake_fetch <- function(
    watershed_group_code = NULL,
    blue_line_key = NULL,
    bbox = NULL,
    area_ha_min = NULL,
    table = "whse_basemapping.fwa_lakes_poly",
    cols = c(
      "waterbody_poly_id", "waterbody_key", "waterbody_type", "area_ha",
      "gnis_name_1", "blue_line_key", "watershed_group_code", "geom"
    ),
    limit = NULL,
    ...
) {
  where <- .frs_build_where(
    watershed_group_code = watershed_group_code,
    blue_line_key = blue_line_key,
    bbox = bbox,
    extra = if (!is.null(area_ha_min)) {
      paste0("area_ha >= ", area_ha_min)
    }
  )

  sql <- paste0(
    "SELECT ", paste(cols, collapse = ", "),
    " FROM ", table,
    where,
    if (!is.null(limit)) paste0(" LIMIT ", as.integer(limit))
  )

  frs_db_query(sql, ...)
}
