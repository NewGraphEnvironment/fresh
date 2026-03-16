#' Fetch Fish Observations
#'
#' Query fish observation events from a bcfishobs table.
#' Filter by species code, watershed group, and/or blue line key.
#'
#' @param species_code Character. Species code (e.g. `"CH"` for chinook,
#'   `"ST"` for steelhead). Default `NULL` (all species).
#' @param watershed_group_code Character. Watershed group code. Default `NULL`.
#' @param blue_line_key Integer. Blue line key. Default `NULL`.
#' @param table Character. Fully qualified table name. Default
#'   `"bcfishobs.fiss_fish_obsrvtn_events_vw"`.
#' @param cols Character vector of column names to select. Default includes
#'   the most commonly used observation attributes.
#' @param limit Integer. Maximum rows to return. Default `NULL`.
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#'
#' @return An `sf` data frame of fish observation events.
#'
#' @family fish
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#' obs <- frs_fish_obs(conn, species_code = "CH",
#'   watershed_group_code = "BULK")
#' DBI::dbDisconnect(conn)
#' }
frs_fish_obs <- function(
    conn,
    species_code = NULL,
    watershed_group_code = NULL,
    blue_line_key = NULL,
    table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
    cols = c(
      "fish_observation_point_id", "species_code", "observation_date",
      "life_stage", "activity", "blue_line_key",
      "downstream_route_measure", "watershed_group_code",
      "wscode_ltree", "localcode_ltree", "geom"
    ),
    limit = NULL
) {
  .frs_validate_identifier(table, "table")
  for (col in cols) .frs_validate_identifier(col, "column")

  clauses <- character(0)

  if (!is.null(species_code)) {
    clauses <- c(clauses, paste0("species_code = ", .frs_quote_string(species_code)))
  }
  if (!is.null(watershed_group_code)) {
    clauses <- c(clauses, paste0("watershed_group_code = ", .frs_quote_string(watershed_group_code)))
  }
  if (!is.null(blue_line_key)) {
    clauses <- c(clauses, paste0("blue_line_key = ", as.integer(blue_line_key)))
  }

  where <- if (length(clauses) > 0) {
    paste0(" WHERE ", paste(clauses, collapse = " AND "))
  } else {
    ""
  }

  sql <- paste0(
    "SELECT ", paste(cols, collapse = ", "),
    " FROM ", table,
    where,
    if (!is.null(limit)) paste0(" LIMIT ", as.integer(limit))
  )

  frs_db_query(conn, sql)
}
