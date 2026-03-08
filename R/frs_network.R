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
#' measures on the same blue line key — network subtraction (upstream of A minus
#' upstream of B) with no spatial clipping needed.
#'
#' @param blue_line_key Integer. Blue line key of the reference point.
#' @param downstream_route_measure Numeric. Downstream route measure of the
#'   downstream boundary.
#' @param upstream_measure Numeric or `NULL`. Downstream route measure of the
#'   upstream boundary. When provided, returns features between the two measures
#'   (network subtraction). Only valid with `direction = "upstream"`.
#' @param tables A named list of table specifications. Each element can be:
#'   - A character string (table name) — uses default columns
#'   - A list with any of: `table`, `cols`, `wscode_col`, `localcode_col`,
#'     `extra_where`
#'
#'   If `NULL` (default), queries FWA streams only.
#' @param direction Character. `"upstream"` (default) or `"downstream"`.
#' @param ... Additional arguments passed to [frs_db_conn()].
#'
#' @return A named list of `sf` data frames (or plain data frames for tables
#'   without geometry). If only one table is queried, returns the data frame
#'   directly.
#'
#' @family traverse
#'
#' @export
#'
#' @examples
#' \dontrun{
#' blk <- 360873822
#'
#' # Everything upstream of a point
#' streams <- frs_network(blk, 166030)
#'
#' # Between two points (subbasin): upstream of Byman minus upstream of Ailport
#' result <- frs_network(blk, 208877, upstream_measure = 233564, tables = list(
#'   streams = "whse_basemapping.fwa_stream_networks_sp",
#'   lakes = "whse_basemapping.fwa_lakes_poly",
#'   crossings = "bcfishpass.crossings",
#'   observations = list(
#'     table = "bcfishpass.observations_vw",
#'     wscode_col = "wscode",
#'     localcode_col = "localcode"
#'   )
#' ))
#' }
frs_network <- function(
    blue_line_key,
    downstream_route_measure,
    upstream_measure = NULL,
    tables = NULL,
    direction = "upstream",
    ...
) {
  direction <- match.arg(direction, c("upstream", "downstream"))

  if (!is.null(upstream_measure)) {
    if (direction != "upstream") {
      stop("upstream_measure only applies when direction = 'upstream'")
    }
    if (upstream_measure <= downstream_route_measure) {
      stop("upstream_measure must be greater than downstream_route_measure")
    }
  }

  if (is.null(tables)) {
    tables <- list(streams = "whse_basemapping.fwa_stream_networks_sp")
  }

  # Normalize: bare strings become list(table = x)
  tables <- lapply(tables, function(x) {
    if (is.character(x) && length(x) == 1) list(table = x) else x
  })

  results <- lapply(tables, function(spec) {
    frs_network_one(
      blue_line_key = blue_line_key,
      downstream_route_measure = downstream_route_measure,
      upstream_measure = upstream_measure,
      spec = spec,
      direction = direction,
      ...
    )
  })

  if (length(results) == 1L) results[[1L]] else results
}


#' @noRd
frs_network_one <- function(blue_line_key, downstream_route_measure,
                            upstream_measure = NULL, spec, direction, ...) {
  tbl <- spec$table
  cols <- spec$cols
  wscode_col <- spec$wscode_col
  localcode_col <- spec$localcode_col
  extra_where <- spec$extra_where

  # Detect waterbody bridge tables
  is_waterbody <- grepl("lakes_poly|wetlands_poly|rivers_poly", tbl)

  if (is_waterbody) {
    frs_network_waterbody(
      blue_line_key, downstream_route_measure,
      upstream_measure = upstream_measure,
      table = tbl, cols = cols, direction = direction, ...
    )
  } else {
    frs_network_direct(
      blue_line_key, downstream_route_measure,
      upstream_measure = upstream_measure,
      table = tbl, cols = cols,
      wscode_col = wscode_col, localcode_col = localcode_col,
      extra_where = extra_where, direction = direction, ...
    )
  }
}


#' @noRd
frs_network_direct <- function(blue_line_key, downstream_route_measure,
                               upstream_measure = NULL,
                               table, cols = NULL, wscode_col = NULL,
                               localcode_col = NULL, extra_where = NULL,
                               direction = "upstream", ...) {
  wscode_col <- wscode_col %||% "wscode_ltree"
  localcode_col <- localcode_col %||% "localcode_ltree"
  cols <- cols %||% frs_default_cols(table)

  fwa_fn <- switch(direction,
    upstream = "whse_basemapping.fwa_upstream",
    downstream = "whse_basemapping.fwa_downstream"
  )

  select_cols <- paste(paste0("s.", cols), collapse = ", ")

  filter_sql <- ""
  if (!is.null(extra_where)) {
    filters <- if (is.character(extra_where)) extra_where else as.character(extra_where)
    filter_sql <- paste0("\n  AND ", paste(filters, collapse = "\n  AND "))
  }

  blk <- as.integer(blue_line_key)
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
      blk, upstream_measure,
      select_cols, table, fwa_fn,
      wscode_col, localcode_col,
      fwa_fn,
      wscode_col, localcode_col, filter_sql
    )
  }

  frs_db_query(sql, ...)
}


#' @noRd
frs_network_waterbody <- function(blue_line_key, downstream_route_measure,
                                  upstream_measure = NULL,
                                  table, cols = NULL, direction = "upstream",
                                  ...) {
  cols <- cols %||% frs_default_cols(table)

  fwa_fn <- switch(direction,
    upstream = "whse_basemapping.fwa_upstream",
    downstream = "whse_basemapping.fwa_downstream"
  )

  select_cols <- paste(paste0("p.", cols), collapse = ", ")
  blk <- as.integer(blue_line_key)
  stream_tbl <- "whse_basemapping.fwa_stream_networks_sp"

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
        "network_wbkeys AS (\n",
        "  SELECT DISTINCT s.waterbody_key\n",
        "  FROM %s s, ref\n",
        "  WHERE %s(\n",
        "    ref.wscode_ltree, ref.localcode_ltree,\n",
        "    s.wscode_ltree, s.localcode_ltree\n",
        "  )\n",
        "  AND s.waterbody_key IS NOT NULL\n",
        ")\n",
        "SELECT %s\n",
        "FROM %s p\n",
        "JOIN network_wbkeys n ON p.waterbody_key = n.waterbody_key"
      ),
      stream_tbl, blk, downstream_route_measure,
      stream_tbl, fwa_fn,
      select_cols, table
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
        "network_wbkeys AS (\n",
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
        "  AND s.waterbody_key IS NOT NULL\n",
        ")\n",
        "SELECT %s\n",
        "FROM %s p\n",
        "JOIN network_wbkeys n ON p.waterbody_key = n.waterbody_key"
      ),
      stream_tbl, blk, downstream_route_measure,
      stream_tbl, blk, upstream_measure,
      stream_tbl, fwa_fn,
      fwa_fn,
      select_cols, table
    )
  }

  frs_db_query(sql, ...)
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
