#' Watershed at Measure
#'
#' Delineate a watershed polygon at a point on the stream network, defined by
#' blue line key and downstream route measure. Wraps the fwapg
#' `fwa_watershedatmeasure()` function.
#'
#' When `upstream_measure` is provided, returns the difference between the
#' downstream and upstream watersheds — the subbasin *between* the two points.
#' The upstream point can be on a different blue line key (e.g. a tributary)
#' by specifying `upstream_blk`.
#'
#' @param blue_line_key Integer. FWA blue line key identifying the stream.
#' @param downstream_route_measure Numeric. Route measure of the downstream
#'   point (metres).
#' @param upstream_measure Numeric or `NULL`. Route measure of an upstream
#'   point. When provided, returns the watershed between the two measures
#'   (downstream minus upstream).
#' @param upstream_blk Integer or `NULL`. Blue line key for the upstream point.
#'   Defaults to `blue_line_key` (same stream). Use when the upstream point is
#'   on a tributary.
#' @param simplify_m Numeric or `NULL`. Simplification tolerance in metres,
#'   applied in the database as
#'   `ST_Normalize(ST_SimplifyPreserveTopology(geom, simplify_m))`, so the
#'   same database returns the same polygon on every call. For a subbasin the
#'   difference is taken first and simplified once, so the shared boundary
#'   is not simplified twice. Two databases on different GEOS versions can
#'   still simplify a ring differently. Default `NULL` (fwapg's polygon
#'   unchanged).
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#'
#' @return An `sf` data frame with a single polygon geometry.
#'
#' @family watershed
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # Watershed upstream of a single point
#' ws <- frs_watershed_at_measure(conn, 360873822, 208877)
#'
#' # Subbasin between two points on the same stream
#' aoi <- frs_watershed_at_measure(conn, 360873822, 208877,
#'   upstream_measure = 233564)
#'
#' # Subbasin with upstream point on a tributary (different BLK)
#' aoi <- frs_watershed_at_measure(conn, 360873822, 165115,
#'   upstream_measure = 838, upstream_blk = 360886221)
#'
#' # Simplified to 50 m for a map
#' ws_map <- frs_watershed_at_measure(conn, 360873822, 208877, simplify_m = 50)
#' DBI::dbDisconnect(conn)
#' }
frs_watershed_at_measure <- function(
    conn,
    blue_line_key,
    downstream_route_measure,
    upstream_measure = NULL,
    upstream_blk = NULL,
    simplify_m = NULL
) {
  if (!is.numeric(blue_line_key) || length(blue_line_key) != 1 || is.na(blue_line_key)) {
    stop("blue_line_key must be a single numeric value")
  }
  if (!is.numeric(downstream_route_measure) || length(downstream_route_measure) != 1 ||
      is.na(downstream_route_measure)) {
    stop("downstream_route_measure must be a single numeric value")
  }
  if (!is.null(upstream_measure)) {
    if (!is.numeric(upstream_measure) || length(upstream_measure) != 1 ||
        is.na(upstream_measure)) {
      stop("upstream_measure must be a single numeric value or NULL")
    }
  }
  if (!is.null(upstream_blk)) {
    if (!is.numeric(upstream_blk) || length(upstream_blk) != 1 || is.na(upstream_blk)) {
      stop("upstream_blk must be a single numeric value or NULL")
    }
  }

  if (!is.null(simplify_m)) .frs_validate_simplify_m(simplify_m)

  # Validate upstream > downstream before hitting the DB
  if (!is.null(upstream_measure)) {
    up_blk <- if (is.null(upstream_blk)) blue_line_key else upstream_blk
    if (up_blk == blue_line_key &&
        upstream_measure <= downstream_route_measure) {
      stop("upstream_measure must be greater than downstream_route_measure")
    }
  }

  if (!is.null(simplify_m)) {
    return(.frs_watershed_simplified(conn, blue_line_key,
      downstream_route_measure, upstream_measure, upstream_blk, simplify_m))
  }

  ws_down <- frs_db_query(conn,
    sprintf(
      "SELECT geom FROM whse_basemapping.fwa_watershedatmeasure(%s, %s)",
      blue_line_key, downstream_route_measure
    )
  )

  if (is.null(upstream_measure)) {
    return(ws_down)
  }

  up_blk <- if (is.null(upstream_blk)) blue_line_key else upstream_blk

  ws_up <- frs_db_query(conn,
    sprintf(
      "SELECT geom FROM whse_basemapping.fwa_watershedatmeasure(%s, %s)",
      up_blk, upstream_measure
    )
  )

  if (!sf::st_intersects(ws_down, ws_up, sparse = FALSE)[1, 1]) {
    stop("upstream watershed does not intersect downstream watershed; ",
         "points may not be on the same network")
  }

  sf::st_difference(ws_down, ws_up)
}


#' Watershed at measure, simplified in one query
#'
#' With an upstream point, the difference and the intersection test come
#' from the same query, so each delineation runs once and the difference is
#' simplified as one polygon.
#'
#' @return An `sf` data frame with a single polygon geometry.
#' @noRd
.frs_watershed_simplified <- function(conn, blue_line_key,
                                      downstream_route_measure,
                                      upstream_measure, upstream_blk,
                                      simplify_m) {
  simplify <- function(g) {
    sprintf("ST_Normalize(ST_SimplifyPreserveTopology(%s, %s))", g,
            .frs_sql_num(simplify_m))
  }

  if (is.null(upstream_measure)) {
    return(frs_db_query(conn, sprintf(
      "SELECT %s AS geom FROM whse_basemapping.fwa_watershedatmeasure(%s, %s)",
      simplify("geom"), blue_line_key, downstream_route_measure
    )))
  }

  up_blk <- if (is.null(upstream_blk)) blue_line_key else upstream_blk

  ws <- frs_db_query(conn, sprintf(paste(
    "SELECT ST_Intersects(d.geom, u.geom) AS intersects,",
    "%s AS geom",
    "FROM whse_basemapping.fwa_watershedatmeasure(%s, %s) d,",
    "whse_basemapping.fwa_watershedatmeasure(%s, %s) u"),
    simplify("ST_Difference(d.geom, u.geom)"),
    blue_line_key, downstream_route_measure, up_blk, upstream_measure
  ))

  if (!isTRUE(ws$intersects[1])) {
    stop("upstream watershed does not intersect downstream watershed; ",
         "points may not be on the same network")
  }

  ws$intersects <- NULL
  # sf::st_difference() drops an empty difference; ST_Difference() returns
  # POLYGON EMPTY. Match the unsimplified path.
  ws[!sf::st_is_empty(ws), ]
}
