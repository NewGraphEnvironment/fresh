#' Join Columns from a Lookup Table onto a Working Table
#'
#' Add columns from any lookup table to a working table via SQL `UPDATE ... SET
#' ... FROM`. This is the generic enrichment step in the habitat pipeline —
#' join channel width for intrinsic potential, upstream area and precipitation
#' for a bankfull width regression ([frs_channel_width()]), or any custom
#' model output.
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
#'   New columns take the source's types, for a table and a subquery alike
#'   (read from the result of `SELECT <cols> FROM <from> LIMIT 0`, so
#'   without a length or precision modifier: `character varying`,
#'   `numeric`, `geometry`; `char(n)` and `bit(n)` become `character
#'   varying` and `bit varying`). A column already on `table` keeps its type.
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
#'                ON l.watershed_feature_id = ua.watershed_feature_id)",
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

  # Type each new column as the source has it (#239, #222): read from the
  # source exactly as the UPDATE below reads it, so a subquery is typed too
  # and an unqualified name resolves through search_path to the same
  # relation. A column the source lacks errors here, before any ALTER.
  col_types <- .frs_query_col_types(conn, from, cols)

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


#' Types of a source's columns, as the database resolves them
#'
#' Prepares `SELECT <cols> FROM <from> _src LIMIT 0` and names each result
#' column's type with `format_type()`. Nothing is fetched or written. The
#' type carries no modifier (`character varying`, not `character
#' varying(4)`), as `information_schema.columns.data_type` did before #239,
#' except that `char(n)` and `bit(n)` become `character varying` and
#' `bit varying`, whose bare forms would mean `char(1)` and `bit(1)`,
#' so columns `frs_col_join()` creates keep the types they had for a table
#' source. Unlike that lookup it types a subquery, names an extension type
#' (`ltree`, `geometry`) rather than `USER-DEFINED`, and resolves an
#' unqualified name through `search_path` once, as the `UPDATE` does.
#'
#' @param conn DBI connection.
#' @param from Character. Table name or parenthesised subquery.
#' @param cols Character vector of validated column names.
#' @return Named character vector, `cols` -> type.
#' @noRd
.frs_query_col_types <- function(conn, from, cols) {
  res <- DBI::dbSendQuery(conn, sprintf(
    "SELECT %s FROM %s _src LIMIT 0",
    paste(sprintf("_src.%s", cols), collapse = ", "), from))
  info <- tryCatch(DBI::dbColumnInfo(res),
                   finally = DBI::dbClearResult(res))
  oids <- info[[".oid"]]
  if (is.null(oids) || length(oids) != length(cols) || anyNA(oids)) {
    stop("could not read the column types of ", from, call. = FALSE)
  }
  # Without a modifier, `character` and `bit` mean char(1) and bit(1), so
  # a char(4) or bit(3) column would be created too narrow, the UPDATE would
  # fail, and the column would stay. Those two (and their arrays) take the
  # varying form, which holds any length; every other type's bare name is
  # its widest form.
  types <- DBI::dbGetQuery(conn, sprintf(
    "SELECT CASE o
              WHEN 'bpchar'::regtype THEN 'character varying'
              WHEN '_bpchar'::regtype THEN 'character varying[]'
              WHEN 'bit'::regtype THEN 'bit varying'
              WHEN '_bit'::regtype THEN 'bit varying[]'
              ELSE format_type(o, NULL)
            END AS type
     FROM unnest(ARRAY[%s]::oid[]) WITH ORDINALITY AS u(o, i) ORDER BY i",
    paste(sprintf("%.0f", as.numeric(oids)), collapse = ", ")))$type
  names(types) <- cols
  types
}
