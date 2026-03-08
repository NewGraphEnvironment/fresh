#' Fetch Fish Observations
#'
#' Query fish observation events from `bcfishobs.fiss_fish_obsrvtn_events_vw`.
#' Filter by species code, watershed group, and/or blue line key.
#'
#' @param species_code Character. Species code (e.g. `"CH"` for chinook,
#'   `"ST"` for steelhead). Default `NULL` (all species).
#' @param watershed_group_code Character. Watershed group code. Default `NULL`.
#' @param blue_line_key Integer. Blue line key. Default `NULL`.
#' @param limit Integer. Maximum rows to return. Default `NULL`.
#' @param ... Additional arguments passed to [frs_db_conn()].
#'
#' @return An `sf` data frame of fish observation events.
#'
#' @family fish
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Chinook observations in the Bulkley
#' obs <- frs_fish_obs(species_code = "CH", watershed_group_code = "BULK")
#' }
frs_fish_obs <- function(
    species_code = NULL,
    watershed_group_code = NULL,
    blue_line_key = NULL,
    limit = NULL,
    ...
) {
  clauses <- character(0)

  if (!is.null(species_code)) {
    clauses <- c(clauses, paste0("species_code = '", species_code, "'"))
  }
  if (!is.null(watershed_group_code)) {
    clauses <- c(clauses, paste0("watershed_group_code = '", watershed_group_code, "'"))
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
    "SELECT * FROM bcfishobs.fiss_fish_obsrvtn_events_vw",
    where,
    if (!is.null(limit)) paste0(" LIMIT ", as.integer(limit))
  )

  frs_db_query(sql, ...)
}
