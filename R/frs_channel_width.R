#' Estimate Channel Width from a Bankfull Regression
#'
#' Write a channel width predicted from upstream drainage area and mean
#' annual precipitation onto a working table, via SQL `UPDATE`. By default
#' it fills only rows where the target column is `NULL`. That gives every
#' segment with both inputs a width, including the first-order streams that
#' `fwa_stream_networks_channel_width` leaves `NULL`, while leaving measured
#' and mapped widths alone. FWA placeholder (`999`) and unmapped segments
#' have no upstream area, so they stay `NULL` unless `value` is given. Point `to` at a new column instead to get an
#' independent estimate to compare against existing widths.
#'
#' The function reads columns that must already be on `table`. It does no
#' network-specific joins. For FWA networks, add them with [frs_col_join()]
#' (see Examples).
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param table Character. Schema-qualified working table to update.
#' @param model Regression to apply. `"poisson2021"` (default), `"hall2007"`,
#'   or a named list of coefficients for a custom power law (see Details).
#' @param to Character. Column to write. Added as `double precision` if
#'   missing. Default `"channel_width"`.
#' @param col_area Character. Upstream drainage area column, in hectares.
#'   Default `"upstream_area_ha"`.
#' @param col_precip Character. Mean annual precipitation column, in
#'   millimetres. Default `"map_upstream"`.
#' @param col_source Character or `NULL`. Column labelling which rows this
#'   call wrote, added as `text` if missing. Default `"<to>_source"`, so a
#'   comparison column (`to = "channel_width_hall"`) never relabels
#'   `channel_width_source`. `NULL` writes no label.
#' @param overwrite Logical. `FALSE` (default) writes only rows where `to` is
#'   `NULL`. `TRUE` rewrites every row: the regression where its inputs
#'   allow, `NULL` elsewhere.
#' @param value Numeric or `NULL`. A width (m) for rows still `NULL` after
#'   the regression, labelled `ASSIGNED`: typically segments with no
#'   upstream area, such as FWA placeholder and unmapped lines. Default
#'   `NULL` leaves them `NULL`.
#' @param verbose Logical. Report how many rows were modelled, assigned
#'   and left `NULL`. Default `TRUE`.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @details
#' Every model is one power law:
#'
#' ```
#' width = k * ((area_ha + a_off) / a_div)^a * ((precip_mm + p_off) / p_div)^b
#' ```
#'
#' \describe{
#'   \item{`"poisson2021"`}{Thorley and Irvine (2021b), Poisson Consulting.
#'     The model behind the `MODELLED` widths in
#'     `fwa_stream_networks_channel_width` (fwapg
#'     `extras/channel_width/sql/channel_width_modelled.sql`):
#'     `k = exp(0.30713)`, `a = b = 0.4577882`, `a_div = 100`,
#'     `p_div = 1000`, `a_off = p_off = 1`, rounded to 2 decimals.
#'     Label `MODELLED_POISSON2021`.}
#'   \item{`"hall2007"`}{The bankfull width regression of the Valley
#'     Confinement Algorithm (Hall et al. 2007), as used by flooded:
#'     `(area_km2 ^ 0.280) * 0.196 * (precip_cm ^ 0.355)`. Here
#'     `k = 0.196`, `a = 0.280`, `b = 0.355`, `a_div = 100` (ha to km2),
#'     `p_div = 10` (mm to cm), no offsets, no rounding. It runs below
#'     poisson2021 except on small catchments, where the crossover depends
#'     on precipitation: about 65 ha at 100 mm, 16 ha at 1000 mm and 5 ha
#'     at 4000 mm. Label `MODELLED_HALL2007`.}
#'   \item{custom}{A named list with numeric `k`, `a`, `b`, `a_div`,
#'     `p_div`, `a_off`, `p_off`, and optionally `digits` (rounding). Label
#'     `MODELLED_CUSTOM`.}
#' }
#'
#' A row is written only where both `area + a_off` and `precip + p_off`
#' are positive, so rows with a `NULL` input stay `NULL`. With poisson2021's
#' offset of 1, an input of 0 is still written. Unlike fwapg, a `NULL`
#' precipitation is not treated as 0.
#'
#' **Matching fwapg.** fwapg computes `MODELLED` once per
#' `wscode_ltree` / `localcode_ltree` pair, from the largest upstream area
#' among that pair's watershed polygons. So every segment on a reach gets the
#' width at its downstream end. To reproduce it, join that group maximum as
#' the area column (second example). On the Bulkley group, that join
#' puts 94% of `MODELLED` rows within 5%, against about 10% for each
#' segment's own area.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # Inputs: upstream area (ha) and mean annual precipitation (mm)
#' conn |>
#'   frs_col_join("working.streams",
#'     from = "(SELECT l.linear_feature_id, ua.upstream_area_ha
#'              FROM fwa_streams_watersheds_lut l
#'              JOIN fwa_watersheds_upstream_area ua
#'                ON l.watershed_feature_id = ua.watershed_feature_id)",
#'     cols = "upstream_area_ha",
#'     by = "linear_feature_id") |>
#'   frs_col_join("working.streams",
#'     from = "fwa_stream_networks_mean_annual_precip",
#'     cols = "map_upstream",
#'     by = c("wscode_ltree", "localcode_ltree"))
#'
#' # Fill NULL widths (first-order streams), 0.5 m where inputs are missing
#' conn |>
#'   frs_channel_width("working.streams", value = 0.5)
#'
#' # Independent estimates alongside the existing widths
#' conn |>
#'   frs_channel_width("working.streams", to = "channel_width_poisson") |>
#'   frs_channel_width("working.streams", model = "hall2007",
#'     to = "channel_width_hall")
#'
#' # fwapg-matching area: the largest upstream area per watershed-code pair
#' conn |>
#'   frs_col_join("working.streams",
#'     from = "(SELECT s.wscode_ltree, s.localcode_ltree,
#'                     max(ua.upstream_area_ha) AS upstream_area_ha
#'              FROM fwa_stream_networks_sp s
#'              JOIN fwa_streams_watersheds_lut l
#'                ON s.linear_feature_id = l.linear_feature_id
#'              JOIN fwa_watersheds_upstream_area ua
#'                ON l.watershed_feature_id = ua.watershed_feature_id
#'              -- the watershed group(s) your table covers
#'              WHERE s.watershed_group_code = 'BULK'
#'              GROUP BY s.wscode_ltree, s.localcode_ltree)",
#'     cols = "upstream_area_ha",
#'     by = c("wscode_ltree", "localcode_ltree"))
#'
#' DBI::dbDisconnect(conn)
#' }
frs_channel_width <- function(conn, table,
                              model = "poisson2021",
                              to = "channel_width",
                              col_area = "upstream_area_ha",
                              col_precip = "map_upstream",
                              col_source = paste0(to, "_source"),
                              overwrite = FALSE,
                              value = NULL,
                              verbose = TRUE) {
  m <- .frs_channel_width_models(model)
  .frs_validate_identifier(table, "table")
  .frs_validate_identifier(to, "to")
  .frs_validate_identifier(col_area, "col_area")
  .frs_validate_identifier(col_precip, "col_precip")
  if (!is.null(col_source)) .frs_validate_identifier(col_source, "col_source")
  stopifnot(is.logical(overwrite), length(overwrite) == 1L, !is.na(overwrite))
  stopifnot(is.logical(verbose), length(verbose) == 1L, !is.na(verbose))
  if (!is.null(value) && (!is.numeric(value) || length(value) != 1L ||
                          !is.finite(value) || value <= 0)) {
    stop("`value` must be a positive finite number or NULL", call. = FALSE)
  }
  # integer64 passes is.numeric() but sprintf() formats its raw bits
  if (!is.null(value)) value <- as.double(value)
  # Unquoted identifiers fold to lower case in Postgres; compare as it does
  to <- tolower(to)
  col_area <- tolower(col_area)
  col_precip <- tolower(col_precip)
  if (!is.null(col_source)) col_source <- tolower(col_source)

  cols_input <- c(col_area, col_precip)
  if (to %in% cols_input) {
    stop("`to` must differ from `col_area` and `col_precip`", call. = FALSE)
  }
  if (!is.null(col_source) && col_source %in% c(cols_input, to)) {
    stop("`col_source` must differ from `to`, `col_area` and `col_precip`",
         call. = FALSE)
  }

  # -- Check the table's columns ----------------------------------------------
  col_types <- .frs_channel_width_col_types(conn, table)
  if (length(col_types) == 0L) {
    stop(sprintf("Table %s not found (or has no columns)", table),
         call. = FALSE)
  }
  for (col in cols_input) {
    if (!col %in% names(col_types)) {
      stop(sprintf(
        "Column %s not found on %s. Add it first with frs_col_join() (see ?frs_channel_width).",
        col, table), call. = FALSE)
    }
  }
  # format_type() carries any typmod: numeric(10,2), character varying(20)
  col_base <- sub("\\(.*$", "", col_types)
  types_num <- c("double precision", "numeric", "real")
  if (to %in% names(col_types) && !col_base[[to]] %in% types_num) {
    stop(sprintf("Column %s exists as %s; expected double precision",
                 to, col_types[[to]]), call. = FALSE)
  }
  if (!is.null(col_source) && col_source %in% names(col_types) &&
      !col_base[[col_source]] %in% c("text", "character varying")) {
    stop(sprintf("Column %s exists as %s; expected text",
                 col_source, col_types[[col_source]]), call. = FALSE)
  }

  # -- Write ------------------------------------------------------------------
  .frs_db_execute(conn, sprintf(
    "ALTER TABLE %s ADD COLUMN IF NOT EXISTS %s double precision", table, to))
  if (!is.null(col_source)) {
    .frs_db_execute(conn, sprintf(
      "ALTER TABLE %s ADD COLUMN IF NOT EXISTS %s text", table, col_source))
  }

  expr <- .frs_channel_width_sql(m, col_area, col_precip)
  guard <- .frs_channel_width_guard(m, col_area, col_precip)
  label <- .frs_quote_string(m$label)

  if (overwrite) {
    # One statement: rows without usable inputs go NULL in the same write,
    # so a failure part-way never leaves the column cleared but unfilled.
    set <- sprintf("%s = CASE WHEN %s THEN %s END", to, guard, expr)
    if (!is.null(col_source)) {
      set <- paste0(set, sprintf(", %s = CASE WHEN %s THEN %s END",
                                 col_source, guard, label))
    }
    n_written <- .frs_db_execute(conn, sprintf("UPDATE %s SET %s", table, set))
  } else {
    set <- paste0(to, " = ", expr)
    if (!is.null(col_source)) set <- paste0(set, ", ", col_source, " = ", label)
    n_written <- .frs_db_execute(conn, sprintf(
      "UPDATE %s SET %s WHERE %s IS NULL AND %s", table, set, to, guard))
  }

  # Counted before the value pass: overwrite writes every row, so modelled
  # rows are those written minus those left NULL
  n_null <- 0L
  if (verbose) {
    n_null <- DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*)::int AS n_null FROM %s WHERE %s IS NULL",
      table, to))$n_null
  }
  n_model <- if (overwrite) n_written - n_null else n_written

  n_assigned <- 0L
  if (!is.null(value)) {
    set <- paste0(to, " = ", .frs_sql_num(value))
    if (!is.null(col_source)) {
      set <- paste0(set, ", ", col_source, " = 'ASSIGNED'")
    }
    n_assigned <- .frs_db_execute(conn, sprintf(
      "UPDATE %s SET %s WHERE %s IS NULL", table, set, to))
  }

  if (verbose) {
    message(sprintf("%s: %d modelled (%s), %d assigned, %d still NULL",
                    to, as.integer(n_model), m$label, as.integer(n_assigned),
                    as.integer(n_null - n_assigned)))
  }

  invisible(conn)
}


#' Resolve a channel width model to its coefficients
#'
#' @param model `"poisson2021"`, `"hall2007"`, or a named list of
#'   coefficients (`k`, `a`, `b`, `a_div`, `p_div`, `a_off`, `p_off`,
#'   optional `digits`).
#' @return Named list: the coefficients, `k_sql` (SQL text for `k`),
#'   `digits` (or `NULL`) and `label`.
#' @noRd
.frs_channel_width_models <- function(model) {
  presets <- list(
    # Thorley & Irvine 2021b (fwapg channel_width_modelled.sql). k stays as
    # SQL text so rounding at 2 dp matches fwapg on .xx5 boundaries.
    poisson2021 = list(
      k = exp(0.30713), k_sql = "exp(0.30713)", a = 0.4577882, b = 0.4577882,
      a_div = 100, p_div = 1000, a_off = 1, p_off = 1, digits = 2,
      label = "MODELLED_POISSON2021"),
    # VCA bankfull width (Hall et al. 2007): km2 and cm/yr
    hall2007 = list(
      k = 0.196, k_sql = "0.196", a = 0.280, b = 0.355,
      a_div = 100, p_div = 10, a_off = 0, p_off = 0, digits = NULL,
      label = "MODELLED_HALL2007")
  )

  if (is.character(model)) {
    if (length(model) != 1L || !model %in% names(presets)) {
      stop(sprintf(
        "Unknown channel width model: %s. Use one of %s, or a list of coefficients",
        paste(model, collapse = ", "),
        paste(sprintf('"%s"', names(presets)), collapse = ", ")),
        call. = FALSE)
    }
    return(presets[[model]])
  }

  if (!is.list(model) || is.null(names(model))) {
    stop("`model` must be a preset name or a named list of coefficients",
         call. = FALSE)
  }
  req <- c("k", "a", "b", "a_div", "p_div", "a_off", "p_off")
  missing <- setdiff(req, names(model))
  if (length(missing) > 0L) {
    stop(sprintf("Custom channel width model is missing: %s",
                 paste(missing, collapse = ", ")), call. = FALSE)
  }
  extra <- setdiff(names(model), c(req, "digits"))
  if (length(extra) > 0L) {
    stop(sprintf("Custom channel width model has unknown fields: %s",
                 paste(extra, collapse = ", ")), call. = FALSE)
  }
  for (nm in req) {
    v <- model[[nm]]
    if (!is.numeric(v) || length(v) != 1L || !is.finite(v)) {
      stop(sprintf("`model$%s` must be a finite numeric scalar", nm),
           call. = FALSE)
    }
  }
  if (model$a_div <= 0 || model$p_div <= 0) {
    stop("`model$a_div` and `model$p_div` must be > 0", call. = FALSE)
  }
  digits <- model$digits
  if (!is.null(digits) && (!is.numeric(digits) || length(digits) != 1L ||
                           !is.finite(digits) || digits < 0 ||
                           digits != round(digits))) {
    stop("`model$digits` must be a non-negative whole number", call. = FALSE)
  }

  # as.double: integer64 passes is.numeric() but sprintf() formats raw bits
  out <- lapply(model[req], as.double)
  out$k_sql <- .frs_sql_num(out$k)
  out["digits"] <- list(digits)
  out$label <- "MODELLED_CUSTOM"
  out
}


#' SQL expression for a channel width model
#'
#' Inputs are cast to double precision: precipitation is an integer column
#' in FWA, and `(map_upstream + 1) / 1000` would otherwise divide as
#' integers.
#'
#' @param m Resolved model from [.frs_channel_width_models()].
#' @param col_area,col_precip Character. Input column names.
#' @return Character scalar SQL expression.
#' @noRd
.frs_channel_width_sql <- function(m, col_area, col_precip) {
  expr <- sprintf(
    "%s * ((%s::double precision + %s) / %s) ^ %s * ((%s::double precision + %s) / %s) ^ %s",
    m$k_sql,
    col_area, .frs_sql_num(m$a_off), .frs_sql_num(m$a_div), .frs_sql_num(m$a),
    col_precip, .frs_sql_num(m$p_off), .frs_sql_num(m$p_div),
    .frs_sql_num(m$b))
  if (is.null(m$digits)) return(expr)
  sprintf("round((%s)::numeric, %d)::double precision", expr,
          as.integer(m$digits))
}


#' WHERE guard: both power-law bases must be positive
#'
#' Postgres errors on a negative base to a fractional power, which would
#' abort the whole UPDATE. A NULL input fails the guard too.
#'
#' @inheritParams .frs_channel_width_sql
#' @return Character scalar SQL predicate.
#' @noRd
.frs_channel_width_guard <- function(m, col_area, col_precip) {
  sprintf(
    "(%s::double precision + %s) > 0 AND (%s::double precision + %s) > 0",
    col_area, .frs_sql_num(m$a_off), col_precip, .frs_sql_num(m$p_off))
}


#' Column names and types of a table
#'
#' Resolves `table` the way the UPDATE will (`to_regclass()`: case folding,
#' `search_path`, temp tables) rather than matching the literal name in
#' `information_schema`.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param table Character. Table name, validated by the caller.
#' @return Named character vector: data type, named by column. Empty when
#'   the table does not resolve.
#' @noRd
.frs_channel_width_col_types <- function(conn, table) {
  res <- DBI::dbGetQuery(conn, sprintf(
    "SELECT a.attname AS column_name,
            format_type(a.atttypid, a.atttypmod) AS data_type
     FROM pg_attribute a
     WHERE a.attrelid = to_regclass(%s)
       AND a.attnum > 0 AND NOT a.attisdropped",
    .frs_quote_string(table)))
  out <- res$data_type
  names(out) <- res$column_name
  out
}
