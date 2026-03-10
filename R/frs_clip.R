#' Clip Spatial Features to an AOI Polygon
#'
#' Clips an `sf` data frame to an area of interest polygon using
#' `sf::st_intersection()`. Handles geometry type cleanup automatically —
#' mixed geometry collections from intersection are filtered to the original
#' geometry type (e.g. polygon, linestring).
#'
#' Typical use: clip network query results (lakes, wetlands, streams) to a
#' watershed polygon from [frs_watershed_at_measure()].
#'
#' @param x An `sf` data frame to clip.
#' @param aoi An `sf` or `sfc` polygon to clip to.
#'
#' @return An `sf` data frame clipped to `aoi`, with geometry type matching
#'   the input. Returns an empty `sf` with the same columns if no features
#'   intersect.
#'
#' @family spatial
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Clip wetlands to a subbasin watershed
#' aoi <- frs_watershed_at_measure(blk, drm, upstream_measure = urm)
#' wetlands <- frs_network(blk, drm, tables = list(
#'   wetlands = "whse_basemapping.fwa_wetlands_poly"
#' ))
#' wetlands_clipped <- frs_clip(wetlands, aoi)
#' }
frs_clip <- function(x, aoi) {
  if (!inherits(x, "sf")) stop("x must be an sf object", call. = FALSE)
  if (!inherits(aoi, c("sf", "sfc"))) {
    stop("aoi must be an sf or sfc object", call. = FALSE)
  }
  if (nrow(x) == 0L) return(x)

  # Detect geometry type before clipping
  geom_type <- unique(sf::st_geometry_type(x, by_geometry = FALSE))

  # Match CRS
  if (sf::st_crs(x) != sf::st_crs(aoi)) {
    aoi <- sf::st_transform(aoi, sf::st_crs(x))
  }

  # Clip
  clipped <- suppressWarnings(sf::st_intersection(x, aoi))

  if (nrow(clipped) == 0L) return(clipped)

  # Extract original geometry type from mixed collections
  type_map <- c(
    POLYGON = "POLYGON", MULTIPOLYGON = "POLYGON",
    LINESTRING = "LINESTRING", MULTILINESTRING = "LINESTRING",
    POINT = "POINT", MULTIPOINT = "POINT"
  )
  extract_type <- type_map[as.character(geom_type)]

  # Only extract if intersection produced mixed geometry collections
  clipped_types <- unique(as.character(sf::st_geometry_type(clipped)))
  has_collection <- any(clipped_types %in% c("GEOMETRYCOLLECTION", "GEOMETRY"))
  if (!is.na(extract_type) && has_collection) {
    clipped <- sf::st_collection_extract(clipped, extract_type)
  }

  clipped
}
