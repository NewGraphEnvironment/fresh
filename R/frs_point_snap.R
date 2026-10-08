#' Snap Points to the Nearest Stream
#'
#' Snaps a whole dataset of points to the stream network in one query and
#' returns each point's network position: `blue_line_key`,
#' `downstream_route_measure`, `watershed_group_code`, `linear_feature_id`,
#' `wscode_ltree`, `localcode_ltree`. Each point is matched by a lateral
#' nearest-neighbour search against the network table, so 10,000 points
#' cost one round trip, not 10,000.
#'
#' Candidates are network segments within `tolerance` of the point,
#' nearest first (ties broken by `linear_feature_id`). Placeholder
#' (`999`) and unmapped (NULL local code) segments are never candidates;
#' `exclude_edge_types` drops more. The measure is clamped to the
#' segment's own measure range and rounded to whole metres, following
#' bcfishpass (`04_pscis.sql`). To score and pick among several
#' candidates per point, write them to a table (`num_features > 1`,
#' `to = `) and pass it to [frs_candidates_pick()].
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param points The points to snap. One of:
#'   - a data frame with coordinate columns `col_x` / `col_y` in `srid`;
#'   - an `sf` object with POINT geometry (its CRS gives the SRID);
#'   - a schema-qualified table name with geometry column `col_geom`
#'     (Point or MultiPoint; the first part of a MultiPoint is used, and
#'     the geometry's own SRID applies, so `srid` is ignored). `col_id`
#'     is required for a table.
#'
#'   Rows with missing coordinates are dropped, as are points farther
#'   than `tolerance` from any candidate segment. In a geographic CRS
#'   (e.g. 4326, 4269), coordinates outside lon/lat range are dropped
#'   with a message.
#' @param ... Must be empty. Catches the pre-0.40.0 `x =` / `y =` call.
#' @param to Character or `NULL`. Schema-qualified destination table. When
#'   given, the result is written there (dropped and recreated) and `conn`
#'   is returned invisibly. Default `NULL` returns an `sf` object.
#' @param col_id Character or `NULL`. Column that identifies each point.
#'   Values must be unique and non-missing. Carried into the output under
#'   the same name. `NULL` (data frame / `sf` only) numbers the rows in a
#'   column named `id_point`.
#' @param col_x,col_y Character. Coordinate columns of a data frame.
#'   Default `"x"`, `"y"`.
#' @param col_geom Character. Geometry column of a table input. Default
#'   `"geom"`.
#' @param srid Integer. SRID of `col_x` / `col_y` for a data frame. Default
#'   `4326` (WGS84 lon/lat).
#' @param col_blk Character or `NULL`. Column holding a per-point
#'   `blue_line_key` hint. A point with a hint snaps only to that stream;
#'   a point whose hint is missing snaps to any stream.
#' @param tolerance Numeric. Maximum snap distance in metres. Default
#'   `100`, the distance bcfishobs accepts for its A/B matches.
#' @param num_features Integer. Candidates kept per point. Default `1`.
#'   When greater than 1 the output gains `candidate_rank` (1 = nearest).
#' @param stream_order_min Integer or `NULL`. Minimum stream order of a
#'   candidate segment.
#' @param exclude_edge_types Integer vector or `NULL`. Edge types that are
#'   never candidates. Default `1425L` (subsurface flow). `NULL` excludes
#'   none. See [frs_edge_types()].
#'
#' @return Without `to`, an `sf` object (EPSG:3005) with one row per
#'   point × candidate: the id column, `linear_feature_id`,
#'   `blue_line_key`, `downstream_route_measure`, `watershed_group_code`,
#'   `wscode_ltree`, `localcode_ltree`, `gnis_name`,
#'   `distance_to_stream`, `candidate_rank` (when `num_features > 1`) and
#'   the snapped point `geom`. With `to`, `conn` invisibly.
#'
#' @details
#' The network table and its column names come from the `fresh.*` options
#' (see `tbl_network`, `blk_col`, `segment_id_col`, `measure_ds_col`,
#' `measure_us_col`, `wscode_col`, `localcode_col`). A custom network table
#' also needs `watershed_group_code`, `gnis_name`, `edge_type`,
#' `stream_order` and `length_metre` columns.
#'
#' Data frame and `sf` points travel to the database as a temporary
#' table, which needs one session for the whole call. That holds for a
#' plain connection and for each mirai worker; it does not hold behind a
#' pooler that switches backends per statement (pgbouncer transaction
#' pooling).
#'
#' @family index
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # Three sampling sites, snapped in one query
#' sites <- data.frame(
#'   site = c("upper", "middle", "lower"),
#'   x = c(-126.52, -126.61, -126.70),
#'   y = c(54.49, 54.58, 54.41)
#' )
#' snapped <- frs_point_snap(conn, sites, col_id = "site", tolerance = 500)
#' snapped[, c("site", "blue_line_key", "downstream_route_measure",
#'             "watershed_group_code", "distance_to_stream")]
#'
#' # Up to three candidate streams per site, ranked by distance
#' frs_point_snap(conn, sites, col_id = "site", tolerance = 1000,
#'   num_features = 3)
#'
#' # A table of crossings, written to a table for frs_candidates_pick()
#' frs_point_snap(conn, "whse_fish.pscis_assessment_svw",
#'   col_id = "stream_crossing_id", tolerance = 150, num_features = 5,
#'   to = "working.pscis_candidates")
#'
#' DBI::dbDisconnect(conn)
#' }
frs_point_snap <- function(
    conn,
    points,
    ...,
    to = NULL,
    col_id = NULL,
    col_x = "x",
    col_y = "y",
    col_geom = "geom",
    srid = 4326L,
    col_blk = NULL,
    tolerance = 100,
    num_features = 1L,
    stream_order_min = NULL,
    exclude_edge_types = 1425L
) {
  dots <- list(...)
  if (missing(points) || is.numeric(points) ||
        any(c("x", "y") %in% names(dots))) {
    stop("frs_point_snap() now takes a dataset: pass ",
         "`points = data.frame(x = ..., y = ...)` (see NEWS for 0.40.0)",
         call. = FALSE)
  }
  if (length(dots) > 0L) {
    stop("unused arguments: ", paste(names(dots), collapse = ", "),
         call. = FALSE)
  }
  .frs_check_scalar_num(tolerance, "tolerance")
  .frs_check_scalar_num(num_features, "num_features")
  # integer64 passes is.numeric() but .frs_sql_num() would render its bits
  tolerance <- as.double(tolerance)
  if (tolerance <= 0) stop("tolerance must be positive", call. = FALSE)
  if (!is.finite(num_features) || num_features < 1) {
    stop("num_features must be a finite number of at least 1", call. = FALSE)
  }
  if (!is.null(stream_order_min)) {
    .frs_check_scalar_num(stream_order_min, "stream_order_min")
  }
  if (!is.null(to)) {
    .frs_validate_identifier(to, "destination table")
    # `to` is dropped before it is built, so it cannot be a table the
    # snap reads: the points table or the network table
    tbls_read <- tolower(c(if (is.character(points)) points,
                           .frs_opt("tbl_network")))
    if (tolower(to) %in% tbls_read) {
      stop("to must differ from the points table and the network table",
           call. = FALSE)
    }
  }
  if (!is.null(col_id)) .frs_check_col_name(col_id, "col_id")
  if (!is.null(col_blk)) .frs_check_col_name(col_blk, "col_blk")

  col_id_out <- if (is.null(col_id)) "id_point" else col_id
  cols_out <- c("linear_feature_id", "blue_line_key",
                "downstream_route_measure", "watershed_group_code",
                "wscode_ltree", "localcode_ltree", "gnis_name",
                "distance_to_stream", "candidate_rank", "geom")
  if (col_id_out %in% cols_out) {
    stop(sprintf("col_id '%s' collides with an output column; rename it",
                 col_id_out), call. = FALSE)
  }

  tmp <- NULL
  on.exit(if (!is.null(tmp)) {
    tryCatch(.frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", tmp)),
             error = function(e) NULL)
  }, add = TRUE)

  if (is.character(points)) {
    pts_sql <- .frs_point_snap_pts_table(conn, points, col_id, col_geom,
                                         col_blk)
  } else if (is.data.frame(points)) {
    df <- .frs_point_snap_df(points, col_id, col_x, col_y, srid, col_blk)
    if (nrow(df$df) == 0L) stop("points has no rows", call. = FALSE)
    tmp <- .frs_db_write_temp(conn, df$df)
    pts_sql <- sprintf(paste0(
      "  SELECT t.id,\n",
      "    ST_Transform(ST_SetSRID(ST_MakePoint(t.x, t.y), %d), 3005) AS geom",
      "%s\n",
      "  FROM %s t\n",
      "  WHERE t.x IS NOT NULL AND t.y IS NOT NULL"),
      df$srid,
      if (is.null(col_blk)) "" else ",\n    t.hint::bigint AS hint",
      tmp)
  } else {
    stop("points must be a data frame, an sf object or a table name",
         call. = FALSE)
  }

  sql <- .frs_point_snap_sql(
    pts_sql, col_id = col_id_out, has_hint = !is.null(col_blk),
    tolerance = tolerance, num_features = num_features,
    stream_order_min = stream_order_min,
    exclude_edge_types = exclude_edge_types)

  if (is.null(to)) return(frs_db_query(conn, sql))

  .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", to))
  .frs_db_execute(conn, sprintf("CREATE TABLE %s AS\n%s", to, sql))
  invisible(conn)
}


#' Stop unless `x` is one non-missing number
#' @noRd
.frs_check_scalar_num <- function(x, name) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x)) {
    stop(sprintf("%s must be a single numeric value", name), call. = FALSE)
  }
  invisible(x)
}


#' Stop unless `x` is one plain column name
#' @noRd
.frs_check_col_name <- function(x, name) {
  if (!is.character(x) || length(x) != 1L ||
        !grepl("^[A-Za-z_][A-Za-z0-9_]*$", x)) {
    stop(sprintf("%s must be a single column name", name), call. = FALSE)
  }
  invisible(x)
}


#' Reduce a data frame or sf of points to the temp-table payload
#'
#' @return List: `df` (`id`, `x`, `y`, and `hint` when `col_blk` is
#'   set) and `srid`.
#' @noRd
.frs_point_snap_df <- function(points, col_id, col_x, col_y, srid,
                               col_blk) {
  n <- nrow(points)

  if (inherits(points, "sf")) {
    geom <- sf::st_geometry(points)
    if (n > 0L && !all(sf::st_geometry_type(geom) == "POINT")) {
      stop("sf points must have POINT geometry", call. = FALSE)
    }
    srid <- sf::st_crs(points)$epsg
    if (is.null(srid) || is.na(srid)) {
      stop("sf points have a CRS with no EPSG code; st_transform() first",
           call. = FALSE)
    }
    # An empty POINT is stored as c(NA, NA)
    xy <- vapply(geom, function(g) as.numeric(g)[1:2], numeric(2))
    x <- xy[1, ]
    y <- xy[2, ]
    points <- sf::st_drop_geometry(points)
  } else {
    .frs_check_scalar_num(srid, "srid")
    .frs_check_col_name(col_x, "col_x")
    .frs_check_col_name(col_y, "col_y")
    if (!all(c(col_x, col_y) %in% names(points))) {
      stop(sprintf("points must have columns %s and %s", col_x, col_y),
           call. = FALSE)
    }
    x <- points[[col_x]]
    y <- points[[col_y]]
    if (!is.numeric(x) || !is.numeric(y)) {
      stop(sprintf("%s and %s must be numeric", col_x, col_y),
           call. = FALSE)
    }
  }

  if (is.null(col_id)) {
    id <- seq_len(n)
  } else {
    if (!col_id %in% names(points)) {
      stop(sprintf("col_id '%s' is not a column of points", col_id),
           call. = FALSE)
    }
    id <- points[[col_id]]
    if (is.factor(id)) id <- as.character(id)
    if (anyNA(id) || anyDuplicated(id) > 0L) {
      stop(sprintf("col_id '%s' must be unique and non-missing", col_id),
           call. = FALSE)
    }
  }

  x <- as.numeric(x)
  y <- as.numeric(y)
  # One lon/lat out of range would make ST_Transform fail the whole batch.
  # Any geographic CRS (4326, 4269, 4617, ...), not only WGS84.
  is_geographic <- tryCatch(isTRUE(sf::st_crs(as.integer(srid))$IsGeographic),
                            error = function(e) FALSE)
  if (is_geographic) {
    bad <- which(!is.na(x) & !is.na(y) &
                   (abs(x) > 180 | abs(y) > 90))
    if (length(bad) > 0L) {
      message(sprintf(
        "%d point(s) with lon/lat out of range dropped (id: %s)",
        length(bad), paste(utils::head(id[bad], 10), collapse = ", ")))
      x[bad] <- NA_real_
      y[bad] <- NA_real_
    }
  }

  df <- data.frame(id = id, x = x, y = y, stringsAsFactors = FALSE)
  if (!is.null(col_blk)) {
    if (!col_blk %in% names(points)) {
      stop(sprintf("col_blk '%s' is not a column of points", col_blk),
           call. = FALSE)
    }
    hint <- points[[col_blk]]
    # An all-NA column arrives as logical; the database needs a number
    if (!is.numeric(hint) && !all(is.na(hint))) {
      stop(sprintf("col_blk '%s' must be numeric", col_blk), call. = FALSE)
    }
    hint <- as.numeric(hint)
    # The hint is cast to bigint in SQL; one bad value would fail the batch
    bad <- which(!is.na(hint) & (!is.finite(hint) | abs(hint) >= 2^63))
    if (length(bad) > 0L) {
      stop(sprintf("col_blk '%s' has values that are not a blue_line_key (id: %s)",
                   col_blk, paste(utils::head(id[bad], 10), collapse = ", ")),
           call. = FALSE)
    }
    df$hint <- hint
  }

  list(df = df, srid = as.integer(srid))
}


#' Points SELECT for a table input
#'
#' Checks in one query that `col_id` is unique and non-missing and that
#' no geometry has SRID 0, then returns the SELECT the snap reads.
#' @noRd
.frs_point_snap_pts_table <- function(conn, table, col_id, col_geom,
                                      col_blk) {
  if (length(table) != 1L) {
    stop("a table of points must be a single table name", call. = FALSE)
  }
  .frs_validate_identifier(table, "points table")
  if (is.null(col_id)) {
    stop("col_id is required for a table of points", call. = FALSE)
  }
  .frs_check_col_name(col_geom, "col_geom")
  id_q <- sprintf('t."%s"', col_id)
  geom_q <- sprintf('t."%s"', col_geom)

  chk <- DBI::dbGetQuery(conn, sprintf(paste0(
    "SELECT count(*) AS n, count(DISTINCT %s) AS n_id,\n",
    "  count(*) FILTER (WHERE ST_SRID(%s) = 0) AS n_srid0\n",
    "FROM %s t"), id_q, geom_q, table))
  if (chk$n != chk$n_id) {
    stop(sprintf("col_id '%s' must be unique and non-missing", col_id),
         call. = FALSE)
  }
  if (chk$n_srid0 > 0) {
    stop(sprintf("%s has %d geometries with SRID 0; set their SRID first",
                 table, as.integer(chk$n_srid0)), call. = FALSE)
  }

  sprintf(paste0(
    "  SELECT %s AS id,\n",
    "    ST_Transform(ST_GeometryN(%s, 1), 3005) AS geom%s\n",
    "  FROM %s t\n",
    "  WHERE %s IS NOT NULL"),
    id_q, geom_q,
    if (is.null(col_blk)) "" else sprintf(',\n    t."%s"::bigint AS hint',
                                          col_blk),
    table, geom_q)
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
