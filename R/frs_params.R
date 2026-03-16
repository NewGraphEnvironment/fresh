#' Load Habitat Model Parameter Sets
#'
#' Load species-specific habitat thresholds from a PostgreSQL table or a local
#' CSV file. Returns a list of parameter sets, one per species, ready for
#' iteration with [lapply()] or `purrr::walk()` over the `frs_break()` /
#' `frs_classify()` pipeline.
#'
#' @param conn A [DBI::DBIConnection-class] object. Required when reading
#'   from a database table. Ignored when `csv` is provided.
#' @param table Character. Schema-qualified table name to read parameters from.
#'   Default `"bcfishpass.parameters_habitat_thresholds"`.
#' @param csv Character or `NULL`. Path to a local CSV file. When provided,
#'   `conn` and `table` are ignored.
#'
#' @return A named list of parameter sets, keyed by species code. Each element
#'   is a list with threshold values and a `ranges` sub-list suitable for
#'   passing to `frs_classify()`.
#'
#' @family parameters
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # Default: bcfishpass parameter tables
#' params <- frs_params(conn)
#' params$CO$spawn_gradient_max
#' params$CO$ranges$spawn
#'
#' # Custom table
#' params <- frs_params(conn, table = "working.my_thresholds")
#'
#' # Local CSV for rapid iteration
#' params <- frs_params(csv = "my_experimental_thresholds.csv")
#'
#' # Drive the pipeline
#' lapply(params, function(p) {
#'   message("Processing: ", p$species_code)
#'   # frs_break(conn, ..., threshold = p$spawn_gradient_max)
#'   # frs_classify(conn, ..., ranges = p$ranges$spawn)
#' })
#'
#' DBI::dbDisconnect(conn)
#' }
frs_params <- function(conn = NULL,
                       table = "bcfishpass.parameters_habitat_thresholds",
                       csv = NULL) {
  if (!is.null(csv)) {
    raw <- utils::read.csv(csv, stringsAsFactors = FALSE)
  } else {
    if (is.null(conn)) {
      stop("conn is required when csv is not provided", call. = FALSE)
    }
    .frs_validate_identifier(table, "table")
    raw <- DBI::dbGetQuery(conn, sprintf("SELECT * FROM %s", table))
  }

  if (nrow(raw) == 0) {
    stop("No parameter rows found", call. = FALSE)
  }
  if (!"species_code" %in% names(raw)) {
    stop("Table must have a 'species_code' column", call. = FALSE)
  }

  # Build a list keyed by species_code
  species_list <- split(raw, raw$species_code)
  params <- lapply(species_list, function(row) {
    row <- as.list(row)

    # Convert numeric fields
    num_fields <- setdiff(names(row), "species_code")
    for (f in num_fields) {
      row[[f]] <- as.numeric(row[[f]])
    }

    # Build ranges sub-list for frs_classify()
    row$ranges <- .frs_build_ranges(row)

    row
  })

  params
}


#' Build ranges list from a parameter row
#'
#' Extracts spawn and rear threshold ranges from a flat parameter list into
#' the `list(column = c(min, max))` format expected by `frs_classify()`.
#'
#' @param row A list with threshold fields (e.g. `spawn_gradient_max`,
#'   `spawn_channel_width_min`, etc.).
#' @return A list with `spawn` and `rear` elements, each a named list of
#'   `c(min, max)` ranges. NULL thresholds are excluded.
#' @noRd
.frs_build_ranges <- function(row) {
  build_range <- function(prefix) {
    ranges <- list()

    gradient_max <- row[[paste0(prefix, "_gradient_max")]]
    if (!is.null(gradient_max) && !is.na(gradient_max)) {
      ranges$gradient <- c(0, gradient_max)
    }

    cw_min <- row[[paste0(prefix, "_channel_width_min")]]
    cw_max <- row[[paste0(prefix, "_channel_width_max")]]
    if (!is.null(cw_min) && !is.na(cw_min)) {
      max_val <- if (!is.null(cw_max) && !is.na(cw_max)) cw_max else Inf
      ranges$channel_width <- c(cw_min, max_val)
    }

    mad_min <- row[[paste0(prefix, "_mad_min")]]
    mad_max <- row[[paste0(prefix, "_mad_max")]]
    if (!is.null(mad_min) && !is.na(mad_min)) {
      max_val <- if (!is.null(mad_max) && !is.na(mad_max)) mad_max else Inf
      ranges$mad_m3s <- c(mad_min, max_val)
    }

    lake_min <- row[[paste0(prefix, "_lake_ha_min")]]
    if (!is.null(lake_min) && !is.na(lake_min)) {
      ranges$lake_ha <- c(lake_min, Inf)
    }

    if (length(ranges) == 0) return(NULL)
    ranges
  }

  list(
    spawn = build_range("spawn"),
    rear = build_range("rear")
  )
}
