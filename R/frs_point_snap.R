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
#' @param exclude_edge_types Integer vector or `NULL`. Edge types to exclude
#'   from snap candidates. Default `1425L` (subsurface flow — underground
#'   conduits). Set to `NULL` to snap to all edge types. Only applies to KNN
#'   path (when `blue_line_key` or `stream_order_min` is provided).
#'   See [frs_edge_types()] for the full lookup table.
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
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
#' conn <- frs_db_conn()
#'
#' # Snap to nearest stream (any)
#' snapped <- frs_point_snap(conn, x = -126.5, y = 54.5)
#'
#' # Snap to a specific stream (Bulkley River)
#' snapped <- frs_point_snap(conn, x = -126.5, y = 54.5,
#'   blue_line_key = 360873822)
#'
#' # Snap to order 4+ streams only
#' snapped <- frs_point_snap(conn, x = -126.5, y = 54.5, stream_order_min = 4)
#' DBI::dbDisconnect(conn)
#' }
frs_point_snap <- function(
    conn,
    x,
    y,
    srid = 4326L,
    tolerance = 5000,
    num_features = 1L,
    blue_line_key = NULL,
    stream_order_min = NULL,
    exclude_edge_types = 1425L
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
      conn = conn, x = x, y = y, srid = srid, tolerance = tolerance,
      num_features = num_features, blue_line_key = blue_line_key,
      stream_order_min = stream_order_min,
      exclude_edge_types = exclude_edge_types
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
  frs_db_query(conn, sql)
}


#' KNN snap against fwa_stream_networks_sp
#'
#' Uses KNN (`<->`) to find nearest stream segments, with measure derivation
#' and boundary clamping following the bcfishpass pattern. Filters out
#' placeholder streams (999 wscode), subsurface flow (edge_type 1425),
#' and unmapped tributaries (NULL localcode).
#'
#' @noRd
frs_point_snap_knn <- function(
    conn, x, y, srid, tolerance, num_features,
    blue_line_key = NULL, stream_order_min = NULL,
    exclude_edge_types = 1425L
) {
  # Build WHERE clauses for stream filtering (includes subsurface guard)
  where_parts <- .frs_snap_guards("s", exclude_edge_types = exclude_edge_types)
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
  frs_db_query(conn, sql)
}


#' Build the bulk snap query
#'
#' One lateral KNN per point against the network table: candidates within
#' `tolerance`, nearest first, ties broken by segment id. The measure is
#' clamped to the segment's own range (bcfishpass `04_pscis.sql` pattern).
#' `candidate_rank` is numbered outside the lateral so the index-ordered
#' nearest-neighbour scan stays intact.
#'
#' @param pts_sql Character. A `SELECT` yielding `id`, `geom` (Point,
#'   EPSG:3005) and, when `has_hint`, `hint` (blue_line_key or NULL).
#' @param col_id Character. Output name of the id column.
#' @param has_hint Logical. Constrain each point to its `hint` stream
#'   (a NULL hint leaves that point unconstrained).
#' @inheritParams frs_point_snap
#' @return Character SQL.
#' @noRd
.frs_point_snap_sql <- function(pts_sql, col_id, has_hint = FALSE,
                                tolerance = 100, num_features = 1L,
                                stream_order_min = NULL,
                                exclude_edge_types = 1425L) {
  col_blk <- .frs_opt("blk_col")
  col_seg <- .frs_opt("segment_id_col")
  col_ds <- .frs_opt("measure_ds_col")
  col_us <- .frs_opt("measure_us_col")

  where_parts <- c(
    sprintf("ST_DWithin(s.geom, p.geom, %s)", .frs_sql_num(tolerance)),
    .frs_snap_guards("s", wscode_col = .frs_opt("wscode_col"),
                     localcode_col = .frs_opt("localcode_col"),
                     exclude_edge_types = exclude_edge_types)
  )
  if (has_hint) {
    where_parts <- c(where_parts, sprintf(
      "(p.hint IS NULL OR s.%s = p.hint)", col_blk))
  }
  if (!is.null(stream_order_min)) {
    where_parts <- c(where_parts, sprintf(
      "s.stream_order >= %d", as.integer(stream_order_min)))
  }

  rank_sql <- if (num_features > 1) {
    paste0(
      "  row_number() OVER (PARTITION BY c.id ",
      "ORDER BY c.distance_to_stream, c.linear_feature_id) AS candidate_rank,\n")
  } else {
    ""
  }

  sprintf(
    paste0(
      "WITH p AS (\n%s\n),\n",
      "c AS (\n",
      "  SELECT p.id, s.*\n",
      "  FROM p\n",
      "  CROSS JOIN LATERAL (\n",
      "    SELECT\n",
      "      s.%s AS linear_feature_id,\n",
      "      s.%s AS blue_line_key,\n",
      "      CEIL(GREATEST(s.%s, FLOOR(LEAST(s.%s,\n",
      "        (ST_LineLocatePoint(s.geom, ST_ClosestPoint(s.geom, p.geom))\n",
      "          * s.length_metre) + s.%s\n",
      "      )))) AS downstream_route_measure,\n",
      "      s.watershed_group_code,\n",
      "      s.%s AS wscode_ltree,\n",
      "      s.%s AS localcode_ltree,\n",
      "      s.gnis_name,\n",
      "      ST_Distance(s.geom, p.geom) AS distance_to_stream,\n",
      "      ST_ClosestPoint(s.geom, p.geom) AS geom\n",
      "    FROM %s s\n",
      "    WHERE %s\n",
      "    ORDER BY s.geom <-> p.geom, s.%s\n",
      "    LIMIT %d\n",
      "  ) s\n",
      ")\n",
      "SELECT\n",
      "  c.id AS \"%s\",\n",
      "  c.linear_feature_id,\n",
      "  c.blue_line_key,\n",
      "  c.downstream_route_measure,\n",
      "  c.watershed_group_code,\n",
      "  c.wscode_ltree,\n",
      "  c.localcode_ltree,\n",
      "  c.gnis_name,\n",
      "  c.distance_to_stream,\n",
      "%s",
      "  c.geom\n",
      "FROM c\n",
      "ORDER BY c.id, c.distance_to_stream, c.linear_feature_id"
    ),
    pts_sql,
    col_seg, col_blk, col_ds, col_us, col_ds,
    .frs_opt("wscode_col"), .frs_opt("localcode_col"),
    .frs_opt("tbl_network"),
    paste(where_parts, collapse = "\n      AND "),
    col_seg,
    as.integer(num_features),
    col_id,
    rank_sql
  )
}
