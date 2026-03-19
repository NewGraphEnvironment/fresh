#' Join Columns from a Lookup Table onto a Working Table
#'
#' Add columns from any lookup table to a working table via SQL `UPDATE ... SET
#' ... FROM`. This is the generic enrichment step in the habitat pipeline —
#' join channel width for intrinsic potential, upstream area and precipitation
#' for flooded's bankfull regression, or any custom model output.
#'
#' Pipeable between [frs_extract()] and [frs_col_generate()]:
#'
#' ```
#' conn |>
#'   frs_extract(...) |>
#'   frs_col_join("working.streams",
#'     from = "fwa_stream_networks_channel_width",
#'     cols = c("channel_width", "channel_width_source"),
#'     by = "linear_feature_id") |>
#'   frs_col_generate("working.streams")
#' ```
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param table Character. Schema-qualified working table to enrich.
#' @param from Character. Source table (or subquery wrapped in parentheses)
#'   containing the columns to join.
#' @param cols Character vector. Column names to add from the source table.
#' @param by Character vector. Join key(s). Unnamed elements match the same
#'   column in both tables. Named elements map working table column (name) to
#'   source column (value): `c(linear_feature_id = "lid")`. Default
#'   `"linear_feature_id"`.
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
#' # Channel width — direct join by linear_feature_id
#' conn |>
#'   frs_col_join("working.streams",
#'     from = "fwa_stream_networks_channel_width",
#'     cols = c("channel_width", "channel_width_source"),
#'     by = "linear_feature_id")
#'
#' # MAD (mean annual discharge) — same pattern
#' conn |>
#'   frs_col_join("working.streams",
#'     from = "fwa_stream_networks_discharge",
#'     cols = "mad_m3s",
#'     by = "linear_feature_id")
#'
#' # Upstream area — two-hop join via subquery
#' conn |>
#'   frs_col_join("working.streams",
#'     from = "(SELECT l.linear_feature_id, ua.upstream_area_ha
#'              FROM fwa_streams_watersheds_lut l
#'              JOIN fwa_watersheds_upstream_area ua
#'                ON l.watershed_feature_id = ua.watershed_feature_id) sub",
#'     cols = "upstream_area_ha",
#'     by = "linear_feature_id")
#'
#' # MAP (mean annual precipitation) — composite key
#' conn |>
#'   frs_col_join("working.streams",
#'     from = "fwa_stream_networks_mean_annual_precip",
#'     cols = "map_upstream",
#'     by = c("wscode_ltree", "localcode_ltree"))
#'
#' DBI::dbDisconnect(conn)
#' }
frs_col_join <- function(conn, table, from, cols,
                         by = "linear_feature_id") {
  .frs_validate_identifier(table, "table")
  # from can be a subquery in parens — only validate if it looks like a table name
  is_subquery <- grepl("^\\(", trimws(from))
  if (!is_subquery) .frs_validate_identifier(from, "source table")
  stopifnot(is.character(cols), length(cols) > 0)
  stopifnot(is.character(by), length(by) > 0)
  for (col in cols) .frs_validate_identifier(col, "column")

  # Discover source column types so new columns get the right type.
  # For real tables, query information_schema. For subqueries, default to text.
  col_types <- rep("text", length(cols))
  names(col_types) <- cols
  if (!is_subquery) {
    src_parts <- strsplit(from, "\\.")[[1]]
    src_table <- src_parts[length(src_parts)]

    # Build schema filter: explicit schema if provided, otherwise search_path
    schema_filter <- if (length(src_parts) == 2) {
      sprintf("table_schema = '%s'", src_parts[1])
    } else {
      "table_schema = ANY(string_to_array(current_setting('search_path'), ', '))"
    }

    type_sql <- sprintf(
      "SELECT column_name, data_type FROM information_schema.columns
       WHERE %s AND table_name = '%s'
         AND column_name IN (%s)",
      schema_filter, src_table,
      paste(sprintf("'%s'", cols), collapse = ", ")
    )
    type_info <- DBI::dbGetQuery(conn, type_sql)
    for (i in seq_len(nrow(type_info))) {
      col_types[type_info$column_name[i]] <- type_info$data_type[i]
    }
  }

  # Add columns if they don't exist
  for (col in cols) {
    sql_add <- sprintf(
      "ALTER TABLE %s ADD COLUMN IF NOT EXISTS %s %s",
      table, col, col_types[col]
    )
    .frs_db_execute(conn, sql_add)
  }

  # Build SET clause
  set_clause <- paste(
    sprintf("%s = _src.%s", cols, cols),
    collapse = ", "
  )

  # Build join conditions
  by_names <- if (is.null(names(by))) by else {
    ifelse(names(by) == "", by, names(by))
  }
  by_values <- unname(by)
  join_clause <- paste(
    sprintf("t.%s = _src.%s", by_names, by_values),
    collapse = " AND "
  )

  sql <- sprintf(
    "UPDATE %s t SET %s FROM %s _src WHERE %s",
    table, set_clause, from, join_clause
  )
  .frs_db_execute(conn, sql)

  invisible(conn)
}
