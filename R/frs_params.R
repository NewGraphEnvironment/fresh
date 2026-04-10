#' Load Habitat Model Parameter Sets
#'
#' Load species-specific habitat thresholds from a PostgreSQL table or a local
#' CSV file. Returns a list of parameter sets, one per species, ready for
#' iteration with [lapply()] or `purrr::walk()` over the `frs_break()` /
#' `frs_classify()` pipeline.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#'   Required when reading from a database table. Use `NULL` when reading
#'   from a CSV file.
#' @param table Character. Schema-qualified table name to read parameters from.
#'   Default `"bcfishpass.parameters_habitat_thresholds"`.
#' @param csv Character or `NULL`. Path to a local CSV file. When provided,
#'   `conn` and `table` are ignored.
#' @param rules_yaml Character or `NULL`. Path to a habitat rules YAML
#'   file. Default reads the bundled
#'   `inst/extdata/parameters_habitat_rules.yaml`. Pass `NULL` to skip
#'   rules entirely (every species falls through to the CSV ranges
#'   path used pre-0.12.0). When a rules file is loaded, each species
#'   listed in the file gets `$rules$spawn` and `$rules$rear` attached
#'   to its params entry. Species not listed in the file fall through
#'   to the CSV ranges path. See the `parameters_habitat_rules.yaml`
#'   header for the rule format.
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
#' # Load species thresholds from bundled test data
#' params <- frs_params(csv = system.file("testdata", "test_params.csv",
#'   package = "fresh"))
#' names(params)
#'
#' # Coho spawning: gradient 0-5.5%, channel width 2m+, MAD 0.16-9999 m3/s
#' params$CO$ranges$spawn
#'
#' # Bull trout rearing: no gradient or MAD constraint, just channel width 1.5m+
#' params$BT$ranges$rear
#'
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # Default: bcfishpass parameter tables (11 species)
#' params <- frs_params(conn)
#'
#' # Drive the pipeline — one iteration per species
#' lapply(params, function(p) {
#'   message(p$species_code, ": gradient max = ", p$spawn_gradient_max)
#'   # frs_break(conn, ..., threshold = p$spawn_gradient_max)
#'   # frs_classify(conn, ..., ranges = p$ranges$spawn)
#' })
#'
#' DBI::dbDisconnect(conn)
#' }
frs_params <- function(conn = NULL,
                       table = "bcfishpass.parameters_habitat_thresholds",
                       csv = NULL,
                       rules_yaml = system.file(
                         "extdata", "parameters_habitat_rules.yaml",
                         package = "fresh")) {
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

    # Convert numeric fields (skip character columns like edge_types)
    char_fields <- c("species_code", "spawn_edge_types", "rear_edge_types")
    num_fields <- setdiff(names(row), char_fields)
    for (f in num_fields) {
      row[[f]] <- as.numeric(row[[f]])
    }

    # Build ranges sub-list for frs_classify()
    row$ranges <- .frs_build_ranges(row)

    row
  })

  # Attach rules from YAML if provided. Rules are validated at parse
  # time so downstream code can trust the structure.
  if (!is.null(rules_yaml) && nzchar(rules_yaml)) {
    rules <- .frs_load_rules(rules_yaml)
    for (sp in names(rules)) {
      if (!is.null(params[[sp]])) {
        params[[sp]]$rules <- rules[[sp]]
      }
    }
  }

  params
}


#' Load and validate a habitat rules YAML file
#'
#' Reads a rules YAML, validates the structure, and returns a named
#' list keyed by species code with `$spawn` and `$rear` rule lists.
#'
#' @param path Character. Path to the YAML file.
#' @return Named list keyed by species code. Each entry has
#'   `$spawn` and `$rear` rule lists. Either may be missing or empty.
#' @noRd
.frs_load_rules <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("rules_yaml file not found: %s", path), call. = FALSE)
  }
  raw <- yaml::read_yaml(path)
  if (length(raw) == 0) {
    return(list())
  }

  valid_predicates <- c("edge_types", "edge_types_explicit",
                        "waterbody_type", "lake_ha_min", "thresholds")

  for (sp in names(raw)) {
    sp_block <- raw[[sp]]
    for (habitat in names(sp_block)) {
      if (!habitat %in% c("spawn", "rear")) {
        stop(sprintf(
          "rules YAML for species %s has unknown habitat block '%s' (expected 'spawn' or 'rear')",
          sp, habitat), call. = FALSE)
      }
      rule_list <- sp_block[[habitat]]
      if (is.null(rule_list) || length(rule_list) == 0) next
      for (i in seq_along(rule_list)) {
        rule <- rule_list[[i]]
        if (!is.list(rule)) {
          stop(sprintf(
            "rules YAML %s/%s rule %d is not a mapping",
            sp, habitat, i), call. = FALSE)
        }
        .frs_validate_rule(rule, sp, habitat, i, valid_predicates)
      }
    }
  }

  raw
}


#' Validate a single rule entry
#'
#' Errors on unknown predicate keys, on `mad` (deferred to #114),
#' on `lake_ha_min` without `waterbody_type: L`, on bad
#' `waterbody_type`, or on a non-logical `thresholds` field.
#'
#' @noRd
.frs_validate_rule <- function(rule, sp, habitat, idx, valid_predicates) {
  keys <- names(rule)

  if ("mad" %in% keys) {
    stop(sprintf(
      paste0("rules YAML %s/%s rule %d uses 'mad' predicate which is ",
             "not supported in Phase 1. ",
             "MAD support is tracked in fresh#114."),
      sp, habitat, idx), call. = FALSE)
  }

  unknown <- setdiff(keys, valid_predicates)
  if (length(unknown) > 0) {
    stop(sprintf(
      "rules YAML %s/%s rule %d has unknown predicates: %s. Valid: %s",
      sp, habitat, idx,
      paste(unknown, collapse = ", "),
      paste(valid_predicates, collapse = ", ")), call. = FALSE)
  }

  if (!is.null(rule$waterbody_type)) {
    wt <- rule$waterbody_type
    if (!is.character(wt) || length(wt) != 1 ||
        !wt %in% c("L", "R", "W")) {
      stop(sprintf(
        "rules YAML %s/%s rule %d waterbody_type must be one of L, R, W (got: %s)",
        sp, habitat, idx, paste(wt, collapse = ", ")), call. = FALSE)
    }
  }

  if (!is.null(rule$lake_ha_min)) {
    if (is.null(rule$waterbody_type) || rule$waterbody_type != "L") {
      stop(sprintf(
        paste0("rules YAML %s/%s rule %d uses lake_ha_min without ",
               "waterbody_type: L"),
        sp, habitat, idx), call. = FALSE)
    }
    if (!is.numeric(rule$lake_ha_min) || length(rule$lake_ha_min) != 1) {
      stop(sprintf(
        "rules YAML %s/%s rule %d lake_ha_min must be a numeric scalar",
        sp, habitat, idx), call. = FALSE)
    }
  }

  if (!is.null(rule$thresholds)) {
    if (!is.logical(rule$thresholds) || length(rule$thresholds) != 1) {
      stop(sprintf(
        "rules YAML %s/%s rule %d thresholds must be a logical scalar",
        sp, habitat, idx), call. = FALSE)
    }
  }
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
