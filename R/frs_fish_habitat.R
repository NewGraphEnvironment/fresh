#' Fetch Modelled Fish Habitat from bcfishpass
#'
#' Query stream segments with habitat model outputs from a bcfishpass table.
#' Filter by watershed group and/or blue line key. Returns segments with
#' barrier, access, and habitat classification columns.
#'
#' @param watershed_group_code Character. Watershed group code. Default `NULL`.
#' @param blue_line_key Integer. Blue line key. Default `NULL`.
#' @param table Character. Fully qualified table name. Default
#'   `"bcfishpass.streams_vw"`.
#' @param cols Character vector of column names to select. Default includes
#'   the most commonly used habitat model attributes.
#' @param limit Integer. Maximum rows to return. Default `NULL`.
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
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
#' conn <- frs_db_conn()
#' habitat <- frs_fish_habitat(conn, watershed_group_code = "BULK",
#'   limit = 100)
#' DBI::dbDisconnect(conn)
#' }
frs_fish_habitat <- function(
    conn,
    watershed_group_code = NULL,
    blue_line_key = NULL,
    table = "bcfishpass.streams_vw",
    cols = c(
      "segmented_stream_id", "blue_line_key", "waterbody_key",
      "downstream_route_measure", "upstream_area_ha", "gnis_name",
      "stream_order", "channel_width", "gradient", "mad_m3s",
      "watershed_group_code", "wscode", "localcode", "geom"
    ),
    limit = NULL
) {
  .frs_validate_identifier(table, "table")
  for (col in cols) .frs_validate_identifier(col, "column")

  clauses <- character(0)

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
