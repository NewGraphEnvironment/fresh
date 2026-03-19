#' Categorize Features by Priority-Ordered Boolean Columns
#'
#' Collapse multiple boolean classification columns into a single categorical
#' column. The first `TRUE` column wins — order of `cols` defines priority.
#' Useful for mapping codes (QGIS categorized renderer), reporting categories,
#' and style registry integration (gq).
#'
#' Pipeable after [frs_classify()]:
#'
#' ```
#' conn |>
#'   frs_classify("working.streams", label = "co_spawning", ...) |>
#'   frs_classify("working.streams", label = "co_rearing", ...) |>
#'   frs_categorize("working.streams", label = "habitat_type",
#'     cols = c("co_spawning", "co_rearing", "accessible"),
#'     values = c("CO_SPAWNING", "CO_REARING", "ACCESSIBLE"),
#'     default = "INACCESSIBLE")
#' ```
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param table Character. Working schema table to update.
#' @param label Character. Column name for the categorical result.
#' @param cols Character vector. Boolean columns to check, in priority order.
#'   First `TRUE` wins.
#' @param values Character vector. Category values corresponding to each
#'   column in `cols`. Must be the same length as `cols`.
#' @param default Character. Value for rows where no column is `TRUE`.
#'   Default `"NONE"`.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # After classifying habitat, collapse to a single mapping code
#' conn |>
#'   frs_categorize("working.streams",
#'     label = "habitat_type",
#'     cols = c("co_spawning", "co_rearing", "co_lake_rearing", "accessible"),
#'     values = c("CO_SPAWNING", "CO_REARING", "CO_LAKE_REARING", "ACCESSIBLE"),
#'     default = "INACCESSIBLE")
#'
#' DBI::dbDisconnect(conn)
#' }
frs_categorize <- function(conn, table, label, cols, values,
                           default = "NONE") {
  .frs_validate_identifier(table, "table")
  .frs_validate_identifier(label, "label column")
  stopifnot(is.character(cols), length(cols) > 0)
  stopifnot(is.character(values), length(values) == length(cols))
  stopifnot(is.character(default), length(default) == 1)
  for (col in cols) .frs_validate_identifier(col, "column")

  # Add label column if it doesn't exist
  sql_add <- sprintf(
    "ALTER TABLE %s ADD COLUMN IF NOT EXISTS %s text DEFAULT NULL",
    table, label
  )
  .frs_db_execute(conn, sql_add)

  # Build CASE WHEN ... THEN ... END
  whens <- vapply(seq_along(cols), function(i) {
    sprintf("WHEN %s IS TRUE THEN %s", cols[i], .frs_quote_string(values[i]))
  }, character(1))

  sql <- sprintf(
    "UPDATE %s SET %s = CASE %s ELSE %s END",
    table, label,
    paste(whens, collapse = " "),
    .frs_quote_string(default)
  )
  .frs_db_execute(conn, sql)

  invisible(conn)
}
