#' Aggregate Features Along the Network from Points
#'
#' For each point in a table, traverse the stream network upstream or
#' downstream and aggregate features (streams, lakes, etc.) found on
#' that network. Wraps `fwa_upstream()` / `fwa_downstream()` with
#' `GROUP BY` aggregation.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param points Character. Table of locations to aggregate from. Must have
#'   `blue_line_key` and `downstream_route_measure` columns (or the
#'   equivalents set via `options()`), plus a unique ID column.
#' @param features Character. Table of features to aggregate (e.g.
#'   classified streams, lakes). Must have wscode/localcode columns.
#' @param metrics Named character vector. Names are output column names,
#'   values are SQL expressions. Example:
#'   `c(length_m = "SUM(ST_Length(f.geom))", count = "COUNT(*)")`.
#' @param id_col Character vector. Column(s) that uniquely identify each
#'   point, used in SELECT and GROUP BY. Default
#'   `c("blue_line_key", "downstream_route_measure")`.
#' @param direction Character. `"upstream"` (default) or `"downstream"`.
#' @param where Character or `NULL`. Optional SQL predicate to filter
#'   features before aggregating (alias `f`). Example:
#'   `"f.accessible IS TRUE"` or `"f.co_spawning IS TRUE"`.
#' @param to Character or `NULL`. If provided, write results to this table.
#'   If `NULL` (default), return a data.frame to R.
#' @param overwrite Logical. If `TRUE`, drop `to` before writing.
#'   Default `TRUE`.
#'
#' @return If `to` is provided, `conn` invisibly (for piping). Otherwise,
#'   a data.frame with one row per point and one column per metric.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' # --- What frs_aggregate output looks like ---
#' # frs_aggregate returns a data.frame: one row per point, one col per metric.
#' # This is what you'd get from the Richfield Creek example below:
#' example_result <- data.frame(
#'   blue_line_key = 360788426,
#'   total_km = 20.1,
#'   spawning_km = 3.2,
#'   rearing_km = 8.7,
#'   n_segments = 52
#' )
#' print(example_result)
#' # Read: "Upstream of the falls on Richfield Creek, there are 20.1 km of
#' # stream, of which 3.2 km is coho spawning and 8.7 km is rearing habitat."
#'
#' \dontrun{
#' # --- Live DB: full pipeline ending with aggregate ---
#' # Question: "How much CO habitat is blocked by the Richfield Creek falls?"
#' conn <- frs_db_conn()
#' options(fresh.wscode_col = "wscode",
#'         fresh.localcode_col = "localcode")
#'
#' params <- frs_params(csv = system.file("testdata", "test_params.csv",
#'   package = "fresh"))
#'
#' # 1. Extract Richfield Creek from fwapg
#' richfield <- frs_db_query(conn,
#'   "SELECT ST_Union(geom) AS geom
#'    FROM whse_basemapping.fwa_stream_networks_sp
#'    WHERE blue_line_key = 360788426")
#'
#' conn |>
#'   frs_extract("whse_basemapping.fwa_streams_vw",
#'     "working.demo_agg",
#'     cols = c("linear_feature_id", "blue_line_key",
#'              "downstream_route_measure", "upstream_route_measure",
#'              "wscode", "localcode",
#'              "gradient", "channel_width", "geom"),
#'     aoi = richfield, overwrite = TRUE)
#'
#' # 2. Break at falls, classify accessibility + CO habitat
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_agg_breaks")
#' DBI::dbExecute(conn,
#'   "CREATE TABLE working.demo_agg_breaks AS
#'    SELECT 360788426 AS blue_line_key,
#'           3460.97::double precision AS downstream_route_measure")
#'
#' co_ranges <- params$CO$ranges$spawn[c("gradient", "channel_width")]
#' co_rear <- params$CO$ranges$rear[c("gradient", "channel_width")]
#'
#' conn |>
#'   frs_classify("working.demo_agg", label = "accessible",
#'     breaks = "working.demo_agg_breaks") |>
#'   frs_classify("working.demo_agg", label = "co_spawning",
#'     ranges = co_ranges) |>
#'   frs_classify("working.demo_agg", label = "co_rearing",
#'     ranges = co_rear)
#'
#' # 3. Aggregate: how much habitat is upstream of the falls (blocked)?
#' blocked <- frs_aggregate(conn,
#'   points = "working.demo_agg_breaks",
#'   features = "working.demo_agg",
#'   metrics = c(
#'     total_km = "ROUND(SUM(ST_Length(f.geom))::numeric / 1000, 1)",
#'     spawning_km = "ROUND(SUM(CASE WHEN f.co_spawning
#'       THEN ST_Length(f.geom) ELSE 0 END)::numeric / 1000, 1)",
#'     rearing_km = "ROUND(SUM(CASE WHEN f.co_rearing
#'       THEN ST_Length(f.geom) ELSE 0 END)::numeric / 1000, 1)",
#'     n_segments = "COUNT(*)"
#'   ),
#'   direction = "upstream")
#'
#' message("Blocked by Richfield Creek falls:")
#' message("  Total: ", blocked$total_km, " km")
#' message("  CO spawning: ", blocked$spawning_km, " km")
#' message("  CO rearing: ", blocked$rearing_km, " km")
#'
#' # Clean up
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_agg")
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_agg_breaks")
#' DBI::dbDisconnect(conn)
#' }
frs_aggregate <- function(conn, points, features, metrics,
                          id_col = c("blue_line_key",
                                     "downstream_route_measure"),
                          direction = "upstream",
                          where = NULL,
                          to = NULL, overwrite = TRUE) {
  .frs_validate_identifier(points, "points table")
  .frs_validate_identifier(features, "features table")
  for (col in id_col) .frs_validate_identifier(col, "id column")
  stopifnot(is.character(metrics), length(metrics) > 0)
  stopifnot(direction %in% c("upstream", "downstream"))

  wsc <- .frs_opt("wscode_col")
  loc <- .frs_opt("localcode_col")
  blk <- .frs_opt("blk_col")
  mds <- .frs_opt("measure_ds_col")

  # Build metric expressions
  cols_metric <- paste(
    sprintf("%s AS %s", metrics, names(metrics)),
    collapse = ",\n       "
  )

  # Network traversal function
  fwa_fn <- if (direction == "upstream") "fwa_upstream" else "fwa_downstream"

  # Feature filter
  where_clause <- if (!is.null(where)) {
    paste("\n     AND", where)
  } else {
    ""
  }

  # Build SELECT and GROUP BY from id columns
  cols_id_select <- paste(paste0("p.", id_col), collapse = ", ")
  cols_id_group <- paste(paste0("p.", id_col), collapse = ", ")

  # Points table may not have wscode/localcode (e.g. a breaks table
  # with just blk + measure). Resolve network position from FWA base
  # table via blk + measure range match.
  sql <- sprintf(
    "SELECT %s,
       %s
     FROM %s p
     JOIN whse_basemapping.fwa_stream_networks_sp ref
       ON ref.blue_line_key = p.%s
       AND p.%s >= ref.downstream_route_measure
       AND p.%s < ref.upstream_route_measure
     JOIN %s f ON %s(
       ref.wscode_ltree, ref.localcode_ltree,
       f.%s, f.%s
     )%s
     GROUP BY %s",
    cols_id_select,
    cols_metric,
    points,
    blk,
    mds, mds,
    features, fwa_fn,
    wsc, loc,
    where_clause,
    cols_id_group
  )

  if (!is.null(to)) {
    .frs_validate_identifier(to, "destination table")
    if (overwrite) {
      .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", to))
    }
    .frs_db_execute(conn, sprintf("CREATE TABLE %s AS %s", to, sql))
    invisible(conn)
  } else {
    DBI::dbGetQuery(conn, sql)
  }
}
