#' Snap a Point to the Nearest FWA Stream
#'
#' Snaps x/y coordinates to the nearest stream segment. When no
#' `blue_line_key` is given, wraps fwapg `fwa_indexpoint()`. When
#' `blue_line_key` is provided, uses KNN against `fwa_stream_networks_sp`
#' filtered to that stream, with measure derivation and boundary clamping
#' (following the bcfishpass pattern).
#'
#' @param x Numeric. Longitude or easting.
#' @param y Numeric. Latitude or northing.
#' @param srid Integer. Spatial reference ID of the input coordinates. Default
#'   `4326` (WGS84 lon/lat).
#' @param tolerance Numeric. Maximum search distance in metres. Default `5000`.
#' @param num_features Integer. Number of candidate matches to return. Default `1`.
#' @param blue_line_key Integer. Optional. When provided, snap only to this
#'   stream. Bypasses `fwa_indexpoint()` and uses KNN against
#'   `fwa_stream_networks_sp` with measure derivation and boundary clamping.
#' @param stream_order_min Integer. Optional. Minimum stream order for snap
#'   candidates. Ignored when `blue_line_key` is provided. Forces KNN path.
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
#' # Snap to nearest stream (any)
#' snapped <- frs_point_snap(x = -126.5, y = 54.5)
#'
#' # Snap to a specific stream (Bulkley River)
#' snapped <- frs_point_snap(x = -126.5, y = 54.5, blue_line_key = 360873822)
#'
#' # Snap to order 4+ streams only
#' snapped <- frs_point_snap(x = -126.5, y = 54.5, stream_order_min = 4)
#' }
frs_point_snap <- function(
    x,
    y,
    srid = 4326L,
    tolerance = 5000,
    num_features = 1L,
    blue_line_key = NULL,
    stream_order_min = NULL,
    ...
) {
  if (!is.numeric(x) || length(x) != 1 || is.na(x)) {
    stop("x must be a single numeric value")
  }
  if (!is.numeric(y) || length(y) != 1 || is.na(y)) {
    stop("y must be a single numeric value")
  }
  if (!is.numeric(srid) || length(srid) != 1 || is.na(srid)) {
    stop("srid must be a single numeric value")
  }
  if (!is.numeric(tolerance) || length(tolerance) != 1 || is.na(tolerance)) {
    stop("tolerance must be a single numeric value")
  }
  if (!is.numeric(num_features) || length(num_features) != 1 || is.na(num_features)) {
    stop("num_features must be a single numeric value")
  }
  if (!is.null(blue_line_key)) {
    if (!is.numeric(blue_line_key) || length(blue_line_key) != 1 || is.na(blue_line_key)) {
      stop("blue_line_key must be a single numeric value")
    }
  }
  if (!is.null(stream_order_min)) {
    if (!is.numeric(stream_order_min) || length(stream_order_min) != 1 || is.na(stream_order_min)) {
      stop("stream_order_min must be a single numeric value")
    }
  }

  # KNN path: blue_line_key or stream_order_min provided

  if (!is.null(blue_line_key) || !is.null(stream_order_min)) {
    return(frs_point_snap_knn(
      x = x, y = y, srid = srid, tolerance = tolerance,
      num_features = num_features, blue_line_key = blue_line_key,
      stream_order_min = stream_order_min, ...
    ))
  }

  # Default path: fwa_indexpoint
  sql <- sprintf(
    paste0(
      "SELECT * FROM whse_basemapping.fwa_indexpoint(",
      "ST_Transform(ST_SetSRID(ST_MakePoint(%s, %s), %s), 3005), %s, %s)"
    ),
    x, y, as.integer(srid), tolerance, as.integer(num_features)
  )
  frs_db_query(sql, ...)
}


#' KNN snap against fwa_stream_networks_sp
#'
#' Uses KNN (`<->`) to find nearest stream segments, with measure derivation
#' and boundary clamping following the bcfishpass pattern. Filters out
#' placeholder streams (999 wscode), subsurface flow (edge_type 1410/1425),
#' and unmapped tributaries (NULL localcode).
#'
#' @noRd
frs_point_snap_knn <- function(
    x, y, srid, tolerance, num_features,
    blue_line_key = NULL, stream_order_min = NULL, ...
) {
  # Build WHERE clauses for stream filtering (includes subsurface guard)
  where_parts <- .frs_snap_guards("s")
  if (!is.null(blue_line_key)) {
    where_parts <- c(where_parts,
      sprintf("s.blue_line_key = %s", as.integer(blue_line_key))
    )
  }
  if (!is.null(stream_order_min)) {
    where_parts <- c(where_parts,
      sprintf("s.stream_order >= %s", as.integer(stream_order_min))
    )
  }

  where_clause <- paste(where_parts, collapse = "\n    AND ")

  sql <- sprintf(
    paste0(
      "WITH pt AS (\n",
      "  SELECT ST_Transform(ST_SetSRID(ST_MakePoint(%s, %s), %s), 3005) AS geom\n",
      "),\n",
      "candidates AS (\n",
      "  SELECT\n",
      "    s.linear_feature_id,\n",
      "    s.gnis_name,\n",
      "    s.wscode_ltree,\n",
      "    s.localcode_ltree,\n",
      "    s.blue_line_key,\n",
      "    s.downstream_route_measure,\n",
      "    s.upstream_route_measure,\n",
      "    s.length_metre,\n",
      "    s.geom,\n",
      "    ST_Distance(s.geom, pt.geom) AS distance_to_stream\n",
      "  FROM whse_basemapping.fwa_stream_networks_sp s, pt\n",
      "  WHERE %s\n",
      "  ORDER BY s.geom <-> pt.geom\n",
      "  LIMIT 20\n",
      ")\n",
      "SELECT\n",
      "  c.linear_feature_id,\n",
      "  c.gnis_name,\n",
      "  c.wscode_ltree,\n",
      "  c.localcode_ltree,\n",
      "  c.blue_line_key,\n",
      "  CEIL(GREATEST(c.downstream_route_measure,\n",
      "    FLOOR(LEAST(c.upstream_route_measure,\n",
      "      (ST_LineLocatePoint(c.geom,\n",
      "        ST_ClosestPoint(c.geom, pt.geom)) * c.length_metre)\n",
      "      + c.downstream_route_measure\n",
      "  )))) AS downstream_route_measure,\n",
      "  c.distance_to_stream,\n",
      "  ST_ClosestPoint(c.geom, pt.geom) AS geom\n",
      "FROM candidates c, pt\n",
      "WHERE c.distance_to_stream <= %s\n",
      "ORDER BY c.distance_to_stream\n",
      "LIMIT %s"
    ),
    x, y, as.integer(srid),
    where_clause,
    tolerance,
    as.integer(num_features)
  )
  frs_db_query(sql, ...)
}
