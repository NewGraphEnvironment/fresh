#' Fetch FWA Wetlands
#'
#' Retrieve wetland polygons from `whse_basemapping.fwa_wetlands_poly`.
#' Filter by watershed group code, blue line key, and/or bounding box.
#'
#' @param watershed_group_code Character. Watershed group code (e.g. `"BULK"`).
#'   Default `NULL`.
#' @param blue_line_key Integer. Blue line key for wetlands on a specific stream.
#'   Default `NULL`.
#' @param bbox Numeric vector of length 4 (`xmin`, `ymin`, `xmax`, `ymax`) in
#'   BC Albers (EPSG:3005). Default `NULL`.
#' @param area_ha_min Numeric. Minimum wetland area in hectares. Default `NULL`.
#' @param limit Integer. Maximum rows to return. Default `NULL` (no limit).
#' @param ... Additional arguments passed to [frs_db_conn()].
#'
#' @return An `sf` data frame of wetland polygons.
#'
#' @family fetch
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # All wetlands in the Bulkley watershed group
#' wetlands <- frs_wetland_fetch(watershed_group_code = "BULK")
#'
#' # Wetlands larger than 5 ha
#' wetlands <- frs_wetland_fetch(watershed_group_code = "BULK", area_ha_min = 5)
#' }
frs_wetland_fetch <- function(
    watershed_group_code = NULL,
    blue_line_key = NULL,
    bbox = NULL,
    area_ha_min = NULL,
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
    "SELECT * FROM whse_basemapping.fwa_wetlands_poly",
    where,
    if (!is.null(limit)) paste0(" LIMIT ", as.integer(limit))
  )

  frs_db_query(sql, ...)
}
