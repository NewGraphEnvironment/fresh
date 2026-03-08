#' Get Pruned Upstream Network
#'
#' Like [frs_network_upstream()] but with additional filters: minimum stream
#' order, maximum gradient, and watershed group restriction. Filtering happens
#' in SQL for efficiency.
#'
#' @param blue_line_key Integer. Blue line key of the reference point.
#' @param downstream_route_measure Numeric. Downstream route measure of the
#'   reference point.
#' @param stream_order_min Integer. Minimum Strahler stream order. Default `NULL`.
#' @param gradient_max Numeric. Maximum gradient (rise/run). Default `NULL`.
#' @param watershed_group_code Character. Restrict to a watershed group. Default
#'   `NULL`.
#' @param extra_where Character vector of additional SQL predicates (applied to
#'   alias `s`). Default `NULL`.
#' @param table Character. Fully qualified table name. Default
#'   `"whse_basemapping.fwa_stream_networks_sp"`.
#' @param cols Character vector of column names to select. Default includes
#'   the most commonly used FWA stream attributes.
#' @param wscode_col Character. Name of the watershed code ltree column.
#'   Default `"wscode_ltree"`. Use `"wscode"` for bcfishpass views.
#' @param localcode_col Character. Name of the local code ltree column.
#'   Default `"localcode_ltree"`. Use `"localcode"` for bcfishpass views.
#' @param ... Additional arguments passed to [frs_db_conn()].
#'
#' @return An `sf` data frame of filtered upstream stream segments.
#'
#' @family prune
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Upstream network from FWA base table, order >= 3
#' pruned <- frs_network_prune(
#'   blue_line_key = 360873822,
#'   downstream_route_measure = 166030,
#'   stream_order_min = 3,
#'   gradient_max = 0.05
#' )
#'
#' # Coho rearing/spawning upstream of Neexdzii Kwa confluence
#' co_habitat <- frs_network_prune(
#'   blue_line_key = 360873822,
#'   downstream_route_measure = 166030.4,
#'   stream_order_min = 4,
#'   watershed_group_code = "BULK",
#'   extra_where = "(s.rearing > 0 OR s.spawning > 0)",
#'   table = "bcfishpass.streams_co_vw",
#'   cols = c("segmented_stream_id", "blue_line_key", "waterbody_key",
#'            "gnis_name", "stream_order", "channel_width", "mapping_code",
#'            "rearing", "spawning", "access", "geom"),
#'   wscode_col = "wscode",
#'   localcode_col = "localcode"
#' )
#' }
frs_network_prune <- function(
    blue_line_key,
    downstream_route_measure,
    stream_order_min = NULL,
    gradient_max = NULL,
    watershed_group_code = NULL,
    extra_where = NULL,
    table = "whse_basemapping.fwa_stream_networks_sp",
    cols = c(
      "linear_feature_id", "blue_line_key", "waterbody_key", "edge_type",
      "gnis_name", "stream_order", "stream_magnitude", "gradient",
      "downstream_route_measure", "upstream_route_measure", "length_metre",
      "watershed_group_code", "wscode_ltree", "localcode_ltree", "geom"
    ),
    wscode_col = "wscode_ltree",
    localcode_col = "localcode_ltree",
    ...
) {
  filters <- character(0)

  if (!is.null(stream_order_min)) {
    filters <- c(filters, paste0("s.stream_order >= ", as.integer(stream_order_min)))
  }
  if (!is.null(gradient_max)) {
    filters <- c(filters, paste0("s.gradient <= ", gradient_max))
  }
  if (!is.null(watershed_group_code)) {
    filters <- c(filters, paste0("s.watershed_group_code = '", watershed_group_code, "'"))
  }
  if (!is.null(extra_where)) {
    filters <- c(filters, extra_where)
  }

  filter_sql <- if (length(filters) > 0) {
    paste0("\n  AND ", paste(filters, collapse = "\n  AND "))
  } else {
    ""
  }

  select_cols <- paste(paste0("s.", cols), collapse = ", ")

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
      "WHERE whse_basemapping.fwa_upstream(\n",
      "  ref.wscode, ref.localcode,\n",
      "  s.%s, s.%s\n",
      ")%s"
    ),
    wscode_col, localcode_col,
    table,
    as.integer(blue_line_key),
    downstream_route_measure,
    select_cols,
    table,
    wscode_col, localcode_col,
    filter_sql
  )

  frs_db_query(sql, ...)
}
