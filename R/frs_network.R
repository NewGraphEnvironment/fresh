#' Query Multiple Tables Upstream or Downstream of a Network Position
#'
#' Point at any position on the FWA stream network and retrieve features from
#' one or more tables — streams, crossings, barriers, fish observations, lakes,
#' wetlands, or any table with ltree watershed codes. Tables with
#' `localcode_ltree` are queried directly via `fwa_upstream()` /
#' `fwa_downstream()`. Tables without (like `fwa_lakes_poly`) are queried via
#' the waterbody_key bridge through the stream network.
#'
#' @param blue_line_key Integer. Blue line key of the reference point.
#' @param downstream_route_measure Numeric. Downstream route measure of the
#'   reference point.
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
#' drm <- 166030.4
#'
#' # Single table (returns sf directly)
#' streams <- frs_network(blk, drm)
#'
#' # Multiple tables (returns named list)
#' result <- frs_network(blk, drm, tables = list(
#'   streams = "whse_basemapping.fwa_stream_networks_sp",
#'   lakes = "whse_basemapping.fwa_lakes_poly",
#'   wetlands = "whse_basemapping.fwa_wetlands_poly",
#'   crossings = list(
#'     table = "bcfishpass.crossings",
#'     cols = c("aggregated_crossings_id", "crossing_source",
#'              "barrier_status", "gnis_stream_name", "geom")
#'   ),
#'   co_habitat = list(
#'     table = "bcfishpass.streams_co_vw",
#'     cols = c("segmented_stream_id", "blue_line_key", "gnis_name",
#'              "stream_order", "mapping_code", "rearing", "spawning", "geom"),
#'     wscode_col = "wscode",
#'     localcode_col = "localcode",
#'     extra_where = "(s.rearing > 0 OR s.spawning > 0)"
#'   )
#' ))
#' }
frs_network <- function(
    blue_line_key,
    downstream_route_measure,
    tables = NULL,
    direction = "upstream",
    ...
) {
  direction <- match.arg(direction, c("upstream", "downstream"))

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
      spec = spec,
      direction = direction,
      ...
    )
  })

  if (length(results) == 1L) results[[1L]] else results
}


#' @noRd
frs_network_one <- function(blue_line_key, downstream_route_measure,
                            spec, direction, ...) {
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
      table = tbl, cols = cols, direction = direction, ...
    )
  } else {
    frs_network_direct(
      blue_line_key, downstream_route_measure,
      table = tbl, cols = cols,
      wscode_col = wscode_col, localcode_col = localcode_col,
      extra_where = extra_where, direction = direction, ...
    )
  }
}


#' @noRd
frs_network_direct <- function(blue_line_key, downstream_route_measure,
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

  sql <- sprintf(
    paste0(
      "WITH ref AS (\n",
      "  SELECT %s AS wscode, %s AS localcode\n",
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
    wscode_col, localcode_col, table,
    as.integer(blue_line_key), downstream_route_measure,
    select_cols, table, fwa_fn,
    wscode_col, localcode_col, filter_sql
  )

  frs_db_query(sql, ...)
}


#' @noRd
frs_network_waterbody <- function(blue_line_key, downstream_route_measure,
                                  table, cols = NULL, direction = "upstream",
                                  ...) {
  cols <- cols %||% frs_default_cols(table)

  fwa_fn <- switch(direction,
    upstream = "whse_basemapping.fwa_upstream",
    downstream = "whse_basemapping.fwa_downstream"
  )

  select_cols <- paste(paste0("p.", cols), collapse = ", ")

  sql <- sprintf(
    paste0(
      "WITH ref AS (\n",
      "  SELECT wscode_ltree, localcode_ltree\n",
      "  FROM whse_basemapping.fwa_stream_networks_sp\n",
      "  WHERE blue_line_key = %s\n",
      "    AND downstream_route_measure <= %s\n",
      "  ORDER BY downstream_route_measure DESC\n",
      "  LIMIT 1\n",
      "),\n",
      "network_wbkeys AS (\n",
      "  SELECT DISTINCT s.waterbody_key\n",
      "  FROM whse_basemapping.fwa_stream_networks_sp s, ref\n",
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
    as.integer(blue_line_key), downstream_route_measure,
    fwa_fn, select_cols, table
  )

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
  } else if (grepl("observations", tbl)) {
    c("fish_observation_point_id", "species_code", "species_name",
      "observation_date", "life_stage", "activity", "blue_line_key",
      "downstream_route_measure", "watershed_group_code", "geom")
  } else {
    # Unknown table — select all
    c("*")
  }
}
