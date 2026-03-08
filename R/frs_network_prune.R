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
#' @param table Character. Fully qualified table name. Default
#'   `"whse_basemapping.fwa_stream_networks_sp"`.
#' @param cols Character vector of column names to select. Default includes
#'   the most commonly used FWA stream attributes.
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
#' # Upstream network, order >= 3, gradient <= 0.05
#' pruned <- frs_network_prune(
#'   blue_line_key = 360873822,
#'   downstream_route_measure = 166030,
#'   stream_order_min = 3,
#'   gradient_max = 0.05
#' )
#' }
frs_network_prune <- function(
    blue_line_key,
    downstream_route_measure,
    stream_order_min = NULL,
    gradient_max = NULL,
    watershed_group_code = NULL,
    table = "whse_basemapping.fwa_stream_networks_sp",
    cols = c(
      "linear_feature_id", "blue_line_key", "waterbody_key", "edge_type",
      "gnis_name", "stream_order", "stream_magnitude", "gradient",
      "downstream_route_measure", "upstream_route_measure", "length_metre",
      "watershed_group_code", "wscode_ltree", "localcode_ltree", "geom"
    ),
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

  extra_where <- if (length(filters) > 0) {
    paste0("\n  AND ", paste(filters, collapse = "\n  AND "))
  } else {
    ""
  }

  select_cols <- paste(paste0("s.", cols), collapse = ", ")

  sql <- sprintf(
    paste0(
      "WITH ref AS (\n",
      "  SELECT wscode_ltree, localcode_ltree\n",
      "  FROM %s\n",
      "  WHERE blue_line_key = %s\n",
      "    AND downstream_route_measure <= %s\n",
      "    AND upstream_route_measure > %s\n",
      "  LIMIT 1\n",
      ")\n",
      "SELECT %s\n",
      "FROM %s s, ref\n",
      "WHERE whse_basemapping.fwa_upstream(\n",
      "  ref.wscode_ltree, ref.localcode_ltree,\n",
      "  s.wscode_ltree, s.localcode_ltree\n",
      ")%s"
    ),
    table,
    as.integer(blue_line_key),
    downstream_route_measure,
    downstream_route_measure,
    select_cols,
    table,
    extra_where
  )

  frs_db_query(sql, ...)
}
