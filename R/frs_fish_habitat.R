#' Fetch Modelled Fish Habitat from bcfishpass
#'
#' Query stream segments with habitat model outputs from `bcfishpass.streams_vw`.
#' Filter by watershed group and/or blue line key. Returns segments with
#' barrier, access, and habitat classification columns.
#'
#' @param watershed_group_code Character. Watershed group code. Default `NULL`.
#' @param blue_line_key Integer. Blue line key. Default `NULL`.
#' @param limit Integer. Maximum rows to return. Default `NULL`.
#' @param ... Additional arguments passed to [frs_db_conn()].
#'
#' @return An `sf` data frame of stream segments with bcfishpass habitat model
#'   columns (barriers, access, gradient, channel width, etc.).
#'
#' @family fish
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Habitat model for the Bulkley
#' habitat <- frs_fish_habitat(watershed_group_code = "BULK", limit = 100)
#' }
frs_fish_habitat <- function(
    watershed_group_code = NULL,
    blue_line_key = NULL,
    limit = NULL,
    ...
) {
  clauses <- character(0)

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
    "SELECT * FROM bcfishpass.streams_vw",
    where,
    if (!is.null(limit)) paste0(" LIMIT ", as.integer(limit))
  )

  frs_db_query(sql, ...)
}
