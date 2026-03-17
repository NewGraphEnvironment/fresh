#' Convert Columns to PostgreSQL Generated Columns from Geometry
#'
#' Replace static columns with PostgreSQL `GENERATED ALWAYS` columns
#' derived from the table's LineStringZM geometry. After this, any
#' operation that modifies geometry (e.g. [frs_break_apply()]) will
#' auto-recompute gradient, route measures, and length — no manual
#' recalculation needed.
#'
#' This mirrors the `bcfishpass.streams` table design where `gradient`,
#' `downstream_route_measure`, `upstream_route_measure`, and `length_metre`
#' are all `GENERATED ALWAYS AS (...)` from the geometry.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param table Character. Schema-qualified working table name
#'   (from [frs_extract()]).
#' @param geom_col Character. Name of the geometry column. Default `"geom"`.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @details
#' Converts these columns (drops if they exist, re-adds as generated):
#'
#' \describe{
#'   \item{`gradient`}{`round(((ST_Z(end) - ST_Z(start)) / ST_Length(geom))::numeric, 4)`}
#'   \item{`downstream_route_measure`}{`ST_M(ST_PointN(geom, 1))`}
#'   \item{`upstream_route_measure`}{`ST_M(ST_PointN(geom, -1))`}
#'   \item{`length_metre`}{`ST_Length(geom)`}
#' }
#'
#' Requires LineStringZM geometry (Z for elevation, M for route measures).
#' FWA stream networks have this by default.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' # --- Why generated columns matter (bundled data) ---
#' # When you split a 500m segment at 10% average gradient, the two
#' # pieces have different actual gradients. Generated columns auto-compute
#' # the correct value from each piece's geometry.
#'
#' d <- readRDS(system.file("extdata", "byman_ailport.rds", package = "fresh"))
#' streams <- d$streams
#'
#' # FWA streams carry Z (elevation) and M (route measure) on every vertex
#' head(sf::st_coordinates(streams[1, ]))
#'
#' \dontrun{
#' # --- Live DB: extract, generate, break ---
#' conn <- frs_db_conn()
#' aoi <- d$aoi
#'
#' # 1. Extract FWA streams (static columns)
#' conn |> frs_extract(
#'   from = "whse_basemapping.fwa_stream_networks_sp",
#'   to = "working.demo_gen",
#'   aoi = aoi, overwrite = TRUE)
#'
#' # 2. Convert to generated columns
#' conn |> frs_col_generate("working.demo_gen")
#'
#' # 3. Break — gradient auto-recomputes on new segments
#' conn |> frs_break("working.demo_gen",
#'   attribute = "gradient", threshold = 0.08)
#'
#' # Verify: all segments have gradient (no NULLs, all accurate)
#' result <- frs_db_query(conn,
#'   "SELECT gradient, geom FROM working.demo_gen")
#' summary(result$gradient)
#' plot(result["gradient"], main = "Gradient (auto-computed after break)")
#'
#' # Clean up
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_gen")
#' DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.breaks")
#' DBI::dbDisconnect(conn)
#' }
frs_col_generate <- function(conn, table, geom_col = "geom") {
  .frs_validate_identifier(table, "table")
  .frs_validate_identifier(geom_col, "geometry column")

  # Column definitions: name → GENERATED ALWAYS AS expression
  generated_defs <- list(
    gradient = sprintf(
      "double precision GENERATED ALWAYS AS (
        round((((ST_Z(ST_PointN(%s, -1)) - ST_Z(ST_PointN(%s, 1)))
                / ST_Length(%s))::numeric), 4)
      ) STORED",
      geom_col, geom_col, geom_col
    ),
    downstream_route_measure = sprintf(
      "double precision GENERATED ALWAYS AS (
        ST_M(ST_PointN(%s, 1))
      ) STORED",
      geom_col
    ),
    upstream_route_measure = sprintf(
      "double precision GENERATED ALWAYS AS (
        ST_M(ST_PointN(%s, -1))
      ) STORED",
      geom_col
    ),
    length_metre = sprintf(
      "double precision GENERATED ALWAYS AS (
        ST_Length(%s)
      ) STORED",
      geom_col
    )
  )

  # For each column: drop if exists, then add as generated
  for (col_name in names(generated_defs)) {
    # DROP — use IF EXISTS so it's safe if column doesn't exist
    sql_drop <- sprintf("ALTER TABLE %s DROP COLUMN IF EXISTS %s",
                        table, col_name)
    .frs_db_execute(conn, sql_drop)

    # ADD as generated
    sql_add <- sprintf("ALTER TABLE %s ADD COLUMN %s %s",
                       table, col_name, generated_defs[[col_name]])
    .frs_db_execute(conn, sql_add)
  }

  invisible(conn)
}
