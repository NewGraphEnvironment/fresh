#' Query Multiple Tables Upstream or Downstream of a Network Position
#'
#' Point at any position on the FWA stream network and retrieve features from
#' one or more tables — streams, crossings, barriers, fish observations, lakes,
#' wetlands, or any table with ltree watershed codes. Tables with
#' `localcode_ltree` are queried directly via `fwa_upstream()` /
#' `fwa_downstream()`. Tables without (like `fwa_lakes_poly`) are queried via
#' the waterbody_key bridge through the stream network.
#'
#' When `upstream_measure` is provided, returns only features *between* the two
#' points — network subtraction (upstream of A minus upstream of B) with no
#' spatial clipping needed. The upstream point can be on a different blue line
#' key (e.g. a tributary) by specifying `upstream_blk`.
#'
#' @param blue_line_key Integer. Blue line key of the reference point.
#' @param downstream_route_measure Numeric. Downstream route measure of the
#'   downstream boundary.
#' @param upstream_measure Numeric or `NULL`. Downstream route measure of the
#'   upstream boundary. When provided, returns features between the two measures
#'   (network subtraction). Only valid with `direction = "upstream"`.
#' @param upstream_blk Integer or `NULL`. Blue line key for the upstream point.
#'   Defaults to `blue_line_key` (same stream). Use when the upstream point is
#'   on a tributary.
#' @param tables A named list of table specifications. Each element can be:
#'   - A character string (table name) — uses default columns
#'   - A list with any of: `table`, `cols`, `wscode_col`, `localcode_col`,
#'     `extra_where` (**Warning:** `extra_where` is raw SQL — never populate
#'     from untrusted user input.)
#'
#'   If `NULL` (default), queries FWA streams only.
#' @param direction Character. `"upstream"` (default) or `"downstream"`.
#' @param include_all Logical. If `TRUE`, include placeholder streams (999
#'   wscode) and unmapped tributaries (NULL localcode). Default `FALSE` filters
#'   these out. Only applied when querying the FWA base table.
#' @param clip An `sf` or `sfc` polygon to clip results to (e.g. from
#'   [frs_watershed_at_measure()]). Default `NULL` (no clipping). Useful for
#'   waterbody polygons that straddle watershed boundaries. See [frs_clip()].
#'   Cannot be used with `to` (clipping is an R-side spatial operation).
#' @param to Character or `NULL`. When provided, write results to working
#'   table(s) on the database instead of returning sf objects. For a single
#'   table, `to` is the exact table name. For multiple tables, `to` is a
#'   prefix and each table name is appended as a suffix (e.g.
#'   `to = "working.byman"` with `streams` and `lakes` creates
#'   `working.byman_streams` and `working.byman_lakes`). Returns `conn`
#'   invisibly for pipe chaining. See Examples.
#' @param overwrite Logical. When `to` is provided, drop existing tables
#'   before writing. Default `TRUE`.
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#'
#' @return When `to` is `NULL`: a named list of `sf` data frames (or plain
#'   data frames for tables without geometry). If only one table is queried,
#'   returns the data frame directly. When `to` is provided: `conn` invisibly,
#'   for pipe chaining with [frs_col_join()], [frs_col_generate()], etc.
#'
#' @family traverse
#'
#' @export
#'
#' @examples
#' # --- What frs_network returns (bundled data) ---
#' d <- readRDS(system.file("extdata", "byman_ailport.rds", package = "fresh"))
#' names(d)  # aoi, streams, co, lakes, roads, highways, fsr, railway
#'
#' message("Streams: ", nrow(d$streams), " | Lakes: ", nrow(d$lakes))
#'
#' # Plot the subbasin — streams colored by gradient, lakes in blue
#' plot(d$streams["gradient"], main = "Byman-Ailport subbasin", reset = FALSE)
#' plot(sf::st_geometry(d$lakes), col = "#4292C644", border = "#2171B5",
#'      add = TRUE)
#'
#' \dontrun{
#' # --- Live DB: multi-table network query ---
#' conn <- frs_db_conn()
#' blk <- 360873822
#'
#' # Plot 1: ALL upstream waterbodies
#' result <- frs_network(conn, blk, 208877, upstream_measure = 233564,
#'   tables = list(
#'     streams = "whse_basemapping.fwa_stream_networks_sp",
#'     lakes = "whse_basemapping.fwa_lakes_poly",
#'     wetlands = "whse_basemapping.fwa_wetlands_poly"
#'   ))
#'
#' plot(sf::st_geometry(result$streams), col = "steelblue",
#'      main = paste("All:", nrow(result$lakes), "lakes,",
#'                   nrow(result$wetlands), "wetlands"))
#' plot(sf::st_geometry(result$lakes), col = "#4292C644",
#'      border = "#2171B5", add = TRUE)
#' plot(sf::st_geometry(result$wetlands), col = "#41AB5D44",
#'      border = "#238B45", add = TRUE)
#'
#' # Plot 2: only waterbodies on coho habitat streams
#' # from = bcfishpass table, extra_where filters by habitat columns
#' # Traversal stays on indexed FWA base table (fast), filter is a cheap join
#' filtered <- frs_network(conn,
#'   blue_line_key = blk,
#'   downstream_route_measure = 208877,
#'   upstream_measure = 233564,
#'   tables = list(
#'     co = list(
#'       table = "bcfishpass.streams_co_vw",
#'       wscode_col = "wscode",
#'       localcode_col = "localcode"),
#'     lakes = list(
#'       table = "whse_basemapping.fwa_lakes_poly",
#'       from = "bcfishpass.streams_co_vw",
#'       extra_where = "spawning > 0 OR rearing > 0"),
#'     wetlands = list(
#'       table = "whse_basemapping.fwa_wetlands_poly",
#'       from = "bcfishpass.streams_co_vw",
#'       extra_where = "spawning > 0 OR rearing > 0")
#'   ))
#' plot(sf::st_geometry(result$streams), col = "steelblue",
#'      main = paste("CO habitat:", nrow(filtered$lakes), "lakes,",
#'                   nrow(filtered$wetlands), "wetlands"))
#' plot(sf::st_geometry(filtered$lakes), col = "#4292C644",
#'      border = "#2171B5", add = TRUE)
#' plot(sf::st_geometry(filtered$wetlands), col = "#41AB5D44",
#'      border = "#238B45", add = TRUE)
#' legend("topright", legend = c("Lakes", "Wetlands"),
#'        fill = c("#4292C644", "#41AB5D44"),
#'        border = c("#2171B5", "#238B45"))
#'
#' # --- DB pipeline: write to table, enrich, classify ---
#' # Stays on PostgreSQL — no R memory bottleneck at scale
#' conn |>
#'   frs_network(blk, 208877, upstream_measure = 233564,
#'     to = "working.demo_pipeline") |>
#'   frs_col_join("working.demo_pipeline",
#'     from = "fwa_stream_networks_channel_width",
#'     cols = c("channel_width", "channel_width_source"),
#'     by = "linear_feature_id") |>
#'   frs_col_generate("working.demo_pipeline")
#'
#' # Read the result when you need it in R
#' enriched <- frs_db_query(conn, "SELECT * FROM working.demo_pipeline")
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_pipeline")
#'
#' DBI::dbDisconnect(conn)
#' }
frs_network <- function(
    conn,
    blue_line_key,
    downstream_route_measure,
    upstream_measure = NULL,
    upstream_blk = NULL,
    tables = NULL,
    direction = "upstream",
    include_all = FALSE,
    clip = NULL,
    to = NULL,
    overwrite = TRUE
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

  direction <- match.arg(direction, c("upstream", "downstream"))

  up_blk <- if (is.null(upstream_blk)) blue_line_key else upstream_blk

  if (!is.null(upstream_measure)) {
    if (direction != "upstream") {
      stop("upstream_measure only applies when direction = 'upstream'")
    }
    if (up_blk == blue_line_key &&
        upstream_measure <= downstream_route_measure) {
      stop("upstream_measure must be greater than downstream_route_measure")
    }
    if (up_blk != blue_line_key) {
      frs_check_upstream(conn, blue_line_key, downstream_route_measure,
                         up_blk, upstream_measure)
    }
  }

  # Validate to/clip mutual exclusivity
  if (!is.null(to) && !is.null(clip)) {
    stop("clip and to cannot both be provided; clip is an R-side spatial ",
         "operation that requires sf objects", call. = FALSE)
  }
  if (!is.null(to)) {
    .frs_validate_identifier(to, "to table")
  }

  if (is.null(tables)) {
    tables <- list(streams = "whse_basemapping.fwa_stream_networks_sp")
  }

  # Normalize: bare strings become list(table = x)
  tables <- lapply(tables, function(x) {
    if (is.character(x) && length(x) == 1) list(table = x) else x
  })

  # Find the first stream table (non-waterbody) as default `from` for
  # waterbody key filtering. Waterbody specs can override via `from`.
  cols_stream_specs <- Filter(function(s) {
    !grepl("lakes_poly|wetlands_poly|rivers_poly", s$table)
  }, tables)
  default_from <- if (length(cols_stream_specs) > 0) {
    cols_stream_specs[[1]]$table
  } else {
    NULL
  }

  # Compute destination table names when writing to DB
  to_names <- NULL
  if (!is.null(to)) {
    if (length(tables) == 1L) {
      to_names <- to
    } else {
      to_names <- paste0(to, "_", names(tables))
    }
    names(to_names) <- names(tables)

    # Overwrite: drop existing tables
    if (overwrite) {
      for (tbl_name in to_names) {
        .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", tbl_name))
      }
    }
  }

  results <- lapply(names(tables), function(nm) {
    dest <- if (!is.null(to_names)) to_names[[nm]] else NULL
    frs_network_one(
      conn = conn,
      blue_line_key = blue_line_key,
      downstream_route_measure = downstream_route_measure,
      upstream_measure = upstream_measure,
      upstream_blk = up_blk,
      spec = tables[[nm]],
      direction = direction,
      include_all = include_all,
      default_from = default_from,
      to = dest
    )
  })
  names(results) <- names(tables)

  # When writing to DB, return conn for piping
  if (!is.null(to)) {
    return(invisible(conn))
  }

  # Clip to AOI if provided
  if (!is.null(clip)) {
    results <- lapply(results, function(res) {
      if (inherits(res, "sf") && nrow(res) > 0L) frs_clip(res, clip) else res
    })
  }

  if (length(results) == 1L) results[[1L]] else results
}


#' @noRd
frs_network_one <- function(conn, blue_line_key, downstream_route_measure,
                            upstream_measure = NULL, upstream_blk = NULL,
                            spec, direction, include_all = FALSE,
                            default_from = NULL, to = NULL) {
  tbl <- spec$table
  cols <- spec$cols
  wscode_col <- spec$wscode_col
  localcode_col <- spec$localcode_col
  extra_where <- spec$extra_where

  up_blk <- if (is.null(upstream_blk)) blue_line_key else upstream_blk

  # Detect waterbody bridge tables
  is_waterbody <- grepl("lakes_poly|wetlands_poly|rivers_poly", tbl)

  if (is_waterbody) {
    # from = table for waterbody key filtering (spec overrides default)
    wb_from <- if (!is.null(spec$from)) spec$from else default_from

    frs_network_waterbody(
      conn, blue_line_key, downstream_route_measure,
      upstream_measure = upstream_measure,
      upstream_blk = up_blk,
      table = tbl, cols = cols, direction = direction,
      include_all = include_all,
      extra_where = extra_where,
      from = wb_from,
      to = to
    )
  } else {
    frs_network_direct(
      conn, blue_line_key, downstream_route_measure,
      upstream_measure = upstream_measure,
      upstream_blk = up_blk,
      table = tbl, cols = cols,
      wscode_col = wscode_col, localcode_col = localcode_col,
      extra_where = extra_where, direction = direction,
      include_all = include_all,
      to = to
    )
  }
}


#' @noRd
frs_network_direct <- function(conn, blue_line_key, downstream_route_measure,
                               upstream_measure = NULL, upstream_blk = NULL,
                               table, cols = NULL, wscode_col = NULL,
                               localcode_col = NULL, extra_where = NULL,
                               direction = "upstream", include_all = FALSE,
                               to = NULL) {
  .frs_validate_identifier(table, "table")
  wscode_col <- if (is.null(wscode_col)) "wscode_ltree" else wscode_col
  localcode_col <- if (is.null(localcode_col)) "localcode_ltree" else localcode_col
  .frs_validate_identifier(wscode_col, "wscode_col")
  .frs_validate_identifier(localcode_col, "localcode_col")
  cols <- if (is.null(cols)) frs_default_cols(table) else cols
  for (col in cols) .frs_validate_identifier(col, "column")

  fwa_fn <- switch(direction,
    upstream = "whse_basemapping.fwa_upstream",
    downstream = "whse_basemapping.fwa_downstream"
  )

  select_cols <- paste(paste0("s.", cols), collapse = ", ")

  filters <- character(0)
  if (!include_all && .is_fwa_stream_table(table)) {
    filters <- .frs_stream_guards("s", wscode_col, localcode_col)
  }
  if (!is.null(extra_where)) {
    extra <- if (is.character(extra_where)) extra_where else as.character(extra_where)
    filters <- c(filters, extra)
  }
  filter_sql <- if (length(filters) > 0) {
    paste0("\n  AND ", paste(filters, collapse = "\n  AND "))
  } else {
    ""
  }

  blk <- as.integer(blue_line_key)
  up_blk <- if (is.null(upstream_blk)) blk else as.integer(upstream_blk)
  stream_tbl <- "whse_basemapping.fwa_stream_networks_sp"

  if (is.null(upstream_measure)) {
    sql <- sprintf(
      paste0(
        "WITH ref AS (\n",
        "  SELECT wscode_ltree AS wscode, localcode_ltree AS localcode\n",
        "  FROM %s\n",
        "  WHERE blue_line_key = %s\n",
        "    AND downstream_route_measure <= %s\n",
        "  ORDER BY downstream_route_measure DESC\n",
        "  LIMIT 1\n",
        ")\n",
        "SELECT %s\n",
        "FROM %s s, ref\n",
        "WHERE %s(\n",
        "  ref.wscode, ref.localcode,\n",
        "  s.%s, s.%s\n",
        ")%s"
      ),
      stream_tbl,
      blk, downstream_route_measure,
      select_cols, table, fwa_fn,
      wscode_col, localcode_col, filter_sql
    )
  } else {
    sql <- sprintf(
      paste0(
        "WITH ref_down AS (\n",
        "  SELECT wscode_ltree AS wscode, localcode_ltree AS localcode\n",
        "  FROM %s\n",
        "  WHERE blue_line_key = %s\n",
        "    AND downstream_route_measure <= %s\n",
        "  ORDER BY downstream_route_measure DESC\n",
        "  LIMIT 1\n",
        "),\n",
        "ref_up AS (\n",
        "  SELECT wscode_ltree AS wscode, localcode_ltree AS localcode\n",
        "  FROM %s\n",
        "  WHERE blue_line_key = %s\n",
        "    AND downstream_route_measure <= %s\n",
        "  ORDER BY downstream_route_measure DESC\n",
        "  LIMIT 1\n",
        ")\n",
        "SELECT %s\n",
        "FROM %s s, ref_down\n",
        "WHERE %s(\n",
        "  ref_down.wscode, ref_down.localcode,\n",
        "  s.%s, s.%s\n",
        ")\n",
        "AND NOT EXISTS (\n",
        "  SELECT 1 FROM ref_up\n",
        "  WHERE %s(\n",
        "    ref_up.wscode, ref_up.localcode,\n",
        "    s.%s, s.%s\n",
        "  )\n",
        ")%s"
      ),
      stream_tbl,
      blk, downstream_route_measure,
      stream_tbl,
      up_blk, upstream_measure,
      select_cols, table, fwa_fn,
      wscode_col, localcode_col,
      fwa_fn,
      wscode_col, localcode_col, filter_sql
    )
  }

  if (!is.null(to)) {
    .frs_db_execute(conn, sprintf("CREATE TABLE %s AS %s", to, sql))
    invisible(NULL)
  } else {
    frs_db_query(conn, sql)
  }
}


#' @noRd
frs_network_waterbody <- function(conn, blue_line_key, downstream_route_measure,
                                  upstream_measure = NULL, upstream_blk = NULL,
                                  table, cols = NULL, direction = "upstream",
                                  include_all = FALSE,
                                  extra_where = NULL, from = NULL,
                                  to = NULL) {
  cols <- if (is.null(cols)) frs_default_cols(table) else cols

  fwa_fn <- switch(direction,
    upstream = "whse_basemapping.fwa_upstream",
    downstream = "whse_basemapping.fwa_downstream"
  )

  select_cols <- paste(paste0("p.", cols), collapse = ", ")
  blk <- as.integer(blue_line_key)
  up_blk <- if (is.null(upstream_blk)) blk else as.integer(upstream_blk)

  # Traversal always on indexed network table (has ltree GiST indexes)
  network_tbl <- .frs_opt("tbl_network")

  # Guards apply to the network traversal CTE (alias "s")
  guard_sql <- ""
  if (!include_all) {
    guards <- .frs_stream_guards("s")
    guard_sql <- paste0("\n  AND ", paste(guards, collapse = "\n  AND "))
  }

  # Filter CTE: when from/extra_where specified, filter wbkeys_network
  # by joining to the from table. Cheap join, no ltree traversal.
  has_filter <- !is.null(from) && !is.null(extra_where)
  if (has_filter) {
    filter_cte <- sprintf(
      paste0(
        ",\n",
        "wbkeys_filtered AS (\n",
        "  SELECT DISTINCT n.waterbody_key\n",
        "  FROM wbkeys_network n\n",
        "  JOIN %s f USING (waterbody_key)\n",
        "  WHERE %s\n",
        ")"
      ),
      from, extra_where
    )
    join_cte <- "wbkeys_filtered"
  } else {
    filter_cte <- ""
    join_cte <- "wbkeys_network"
  }

  if (is.null(upstream_measure)) {
    sql <- sprintf(
      paste0(
        "WITH ref AS (\n",
        "  SELECT wscode_ltree, localcode_ltree\n",
        "  FROM %s\n",
        "  WHERE blue_line_key = %s\n",
        "    AND downstream_route_measure <= %s\n",
        "  ORDER BY downstream_route_measure DESC\n",
        "  LIMIT 1\n",
        "),\n",
        "wbkeys_network AS (\n",
        "  SELECT DISTINCT s.waterbody_key\n",
        "  FROM %s s, ref\n",
        "  WHERE %s(\n",
        "    ref.wscode_ltree, ref.localcode_ltree,\n",
        "    s.wscode_ltree, s.localcode_ltree\n",
        "  )\n",
        "  AND s.waterbody_key IS NOT NULL%s\n",
        ")%s\n",
        "SELECT %s\n",
        "FROM %s p\n",
        "JOIN %s n ON p.waterbody_key = n.waterbody_key"
      ),
      network_tbl, blk, downstream_route_measure,
      network_tbl, fwa_fn,
      guard_sql,
      filter_cte,
      select_cols, table, join_cte
    )
  } else {
    sql <- sprintf(
      paste0(
        "WITH ref_down AS (\n",
        "  SELECT wscode_ltree, localcode_ltree\n",
        "  FROM %s\n",
        "  WHERE blue_line_key = %s\n",
        "    AND downstream_route_measure <= %s\n",
        "  ORDER BY downstream_route_measure DESC\n",
        "  LIMIT 1\n",
        "),\n",
        "ref_up AS (\n",
        "  SELECT wscode_ltree, localcode_ltree\n",
        "  FROM %s\n",
        "  WHERE blue_line_key = %s\n",
        "    AND downstream_route_measure <= %s\n",
        "  ORDER BY downstream_route_measure DESC\n",
        "  LIMIT 1\n",
        "),\n",
        "wbkeys_network AS (\n",
        "  SELECT DISTINCT s.waterbody_key\n",
        "  FROM %s s, ref_down\n",
        "  WHERE %s(\n",
        "    ref_down.wscode_ltree, ref_down.localcode_ltree,\n",
        "    s.wscode_ltree, s.localcode_ltree\n",
        "  )\n",
        "  AND NOT EXISTS (\n",
        "    SELECT 1 FROM ref_up\n",
        "    WHERE %s(\n",
        "      ref_up.wscode_ltree, ref_up.localcode_ltree,\n",
        "      s.wscode_ltree, s.localcode_ltree\n",
        "    )\n",
        "  )\n",
        "  AND s.waterbody_key IS NOT NULL%s\n",
        ")%s\n",
        "SELECT %s\n",
        "FROM %s p\n",
        "JOIN %s n ON p.waterbody_key = n.waterbody_key"
      ),
      network_tbl, blk, downstream_route_measure,
      network_tbl, up_blk, upstream_measure,
      network_tbl, fwa_fn,
      fwa_fn,
      guard_sql,
      filter_cte,
      select_cols, table, join_cte
    )
  }

  if (!is.null(to)) {
    .frs_db_execute(conn, sprintf("CREATE TABLE %s AS %s", to, sql))
    invisible(NULL)
  } else {
    frs_db_query(conn, sql)
  }
}


#' @noRd
frs_default_cols <- function(table) {
  tbl <- tolower(table)
  if (grepl("fwa_stream_networks_sp", tbl)) {
    c("linear_feature_id", "blue_line_key", "waterbody_key", "edge_type",
      "gnis_name", "stream_order", "stream_magnitude", "gradient",
      "downstream_route_measure", "upstream_route_measure", "length_metre",
      "watershed_group_code", "wscode_ltree", "localcode_ltree", "geom")
  } else if (grepl("lakes_poly|wetlands_poly", tbl)) {
    c("waterbody_key", "waterbody_type", "gnis_name_1", "area_ha",
      "blue_line_key", "watershed_group_code", "geom")
  } else if (grepl("rivers_poly", tbl)) {
    c("waterbody_key", "gnis_name_1", "area_ha",
      "blue_line_key", "watershed_group_code", "geom")
  } else if (grepl("crossings", tbl)) {
    c("aggregated_crossings_id", "crossing_source", "crossing_type_code",
      "barrier_status", "pscis_status", "blue_line_key",
      "downstream_route_measure", "gnis_stream_name", "stream_order",
      "watershed_group_code", "geom")
  } else if (grepl("barriers", tbl)) {
    c("barrier_type", "barrier_name", "blue_line_key",
      "downstream_route_measure", "watershed_group_code", "geom")
  } else if (grepl("falls", tbl)) {
    c("falls_id", "falls_name", "height_m", "barrier_ind",
      "blue_line_key", "downstream_route_measure",
      "watershed_group_code", "geom")
  } else if (grepl("obsrvtn_events", tbl)) {
    c("fish_observation_point_id", "species_code",
      "observation_date", "life_stage", "activity", "blue_line_key",
      "downstream_route_measure", "watershed_group_code", "geom")
  } else if (grepl("observations", tbl)) {
    c("fish_observation_point_id", "species_code", "species_name",
      "observation_date", "life_stage", "activity", "blue_line_key",
      "downstream_route_measure", "watershed_group_code", "geom")
  } else {
    # Unknown table — select all
    c("*")
  }
}


#' @noRd
frs_check_upstream <- function(conn, down_blk, down_drm, up_blk, up_drm) {
  sql <- sprintf(
    paste0(
      "WITH ref_down AS (\n",
      "  SELECT wscode_ltree, localcode_ltree\n",
      "  FROM whse_basemapping.fwa_stream_networks_sp\n",
      "  WHERE blue_line_key = %s\n",
      "    AND downstream_route_measure <= %s\n",
      "  ORDER BY downstream_route_measure DESC\n",
      "  LIMIT 1\n",
      "),\n",
      "ref_up AS (\n",
      "  SELECT wscode_ltree, localcode_ltree\n",
      "  FROM whse_basemapping.fwa_stream_networks_sp\n",
      "  WHERE blue_line_key = %s\n",
      "    AND downstream_route_measure <= %s\n",
      "  ORDER BY downstream_route_measure DESC\n",
      "  LIMIT 1\n",
      ")\n",
      "SELECT whse_basemapping.fwa_upstream(\n",
      "  ref_down.wscode_ltree, ref_down.localcode_ltree,\n",
      "  ref_up.wscode_ltree, ref_up.localcode_ltree\n",
      ") AS is_upstream\n",
      "FROM ref_down, ref_up"
    ),
    as.integer(down_blk), down_drm,
    as.integer(up_blk), up_drm
  )
  result <- frs_db_query(conn, sql)
  if (nrow(result) == 0 || !isTRUE(result$is_upstream)) {
    stop("upstream point (blk ", up_blk, ") is not upstream of downstream ",
         "point (blk ", down_blk, "); points may not be on the same network")
  }
  invisible(TRUE)
}
