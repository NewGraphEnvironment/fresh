#' Snap a Point to the Nearest FWA Stream
#'
#' Wraps the fwapg `fwa_indexpoint()` function to snap x/y coordinates to the
#' nearest stream segment. Returns the snapped point with its blue line key,
#' downstream route measure, and distance to stream.
#'
#' @param x Numeric. Longitude or easting.
#' @param y Numeric. Latitude or northing.
#' @param srid Integer. Spatial reference ID of the input coordinates. Default
#'   `4326` (WGS84 lon/lat).
#' @param tolerance Numeric. Maximum search distance in metres. Default `5000`.
#' @param num_features Integer. Number of candidate matches to return. Default `1`.
#' @param ... Additional arguments passed to [frs_db_conn()].
#'
#' @return An `sf` data frame with columns: `linear_feature_id`, `gnis_name`,
#'   `blue_line_key`, `downstream_route_measure`, `distance_to_stream`, and
#'   snapped point `geom`.
#'
#' @family index
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Snap a lon/lat point to the nearest stream
#' snapped <- frs_point_snap(x = -126.5, y = 54.5)
#' snapped$blue_line_key
#' snapped$downstream_route_measure
#' }
frs_point_snap <- function(
    x,
    y,
    srid = 4326L,
    tolerance = 5000,
    num_features = 1L,
    ...
) {
  sql <- sprintf(
    paste0(
      "SELECT * FROM whse_basemapping.fwa_indexpoint(",
      "ST_Transform(ST_SetSRID(ST_MakePoint(%s, %s), %s), 3005), %s, %s)"
    ),
    x, y, as.integer(srid), tolerance, as.integer(num_features)
  )
  frs_db_query(sql, ...)
}
