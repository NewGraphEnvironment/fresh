#' Build SQL predicates for one species' habitat classification
#'
#' Pure-R helper: takes one species' rules + ranges from
#' [frs_habitat_species()] and returns a named list of SQL boolean
#' expressions ("predicates") — the raw yes/no questions that
#' [frs_habitat_classify()] embeds in `CASE WHEN <pred> THEN TRUE ...`
#' to produce the per-species habitat columns.
#'
#' Returns four predicates per call: `spawn`, `rear`, `lake_rear`,
#' `wetland_rear`. Each is a fragment that references columns aliased
#' as `s.` (the segmented streams table). Caller is responsible for
#' embedding them in a complete query.
#'
#' Two paths are supported, selected per habitat type by what's
#' present in `sp_params`:
#'
#' 1. **Rules path** — when `sp_params$rules$<spawn|rear>` is non-NULL,
#'    the rules YAML is compiled to SQL via [.frs_rules_to_sql()].
#'    CSV thresholds (gradient + channel_width) are passed as the
#'    inheritance fallback for rules that omit explicit thresholds.
#' 2. **CSV-ranges path** — pre-rules behaviour. Builds the SQL
#'    directly from `sp_params$ranges` + `sp_params$<spawn|rear>_edge_types`.
#'
#' Lake / wetland rearing predicates are gated on the presence of a
#' `waterbody_type: L` / `waterbody_type: W` rule in `rear:`. Without
#' the rule, the predicate is `"FALSE"` — the species is not lake or
#' wetland-rearing. With the rule, an optional `lake_ha_min` /
#' `wetland_ha_min` filters the polygon join.
#'
#' Segments must still fall within the species' rear channel-width
#' window for lake / wetland rearing.
#'
#' @param sp_params A single-species params list as produced by one
#'   element of [frs_habitat_species()]. Must contain `species_code`,
#'   `spawn_gradient_min`, `spawn_gradient_max`, `ranges`, optionally
#'   `rules`, optionally `spawn_edge_types` / `rear_edge_types`.
#' @return A named list with four character scalars: `spawn`, `rear`,
#'   `lake_rear`, `wetland_rear`. Each is an SQL boolean expression
#'   suitable for embedding in `CASE WHEN ... THEN TRUE ELSE FALSE
#'   END`. Predicates reference the segmented streams alias `s.`.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' \dontrun{
#' params <- frs_params()
#' params_fresh <- read.csv(system.file("extdata",
#'   "parameters_fresh.csv", package = "fresh"))
#' species_params <- frs_habitat_species("CO", params, params_fresh)
#'
#' preds <- frs_habitat_predicates(species_params[[1]])
#' preds$spawn
#' #> "s.gradient >= 0 AND s.gradient <= 0.0549 AND ..."
#' preds$lake_rear
#' #> "FALSE"  (CO has no waterbody_type: L rule under bcfishpass)
#' }
frs_habitat_predicates <- function(sp_params) {
  stopifnot(is.list(sp_params),
            !is.null(sp_params[["species_code"]]))

  params_sp <- sp_params$params_sp
  if (is.null(params_sp)) {
    stop("sp_params must contain `params_sp` (per-species YAML/CSV merge)",
         call. = FALSE)
  }

  # Edge-type filter helper: comma-separated category names ->
  # SQL `s.edge_type IN (...)` clause.
  edge_filter <- function(types_str) {
    if (is.null(types_str) || is.na(types_str) || !nzchar(types_str)) {
      return(NULL)
    }
    cats <- trimws(strsplit(types_str, ",")[[1]])
    codes <- unlist(lapply(cats, function(cat) {
      frs_edge_types(category = cat)$edge_type
    }))
    if (length(codes) == 0) return(NULL)
    sprintf("s.edge_type IN (%s)", paste(codes, collapse = ", "))
  }

  # --- spawn predicate ---
  if (!is.null(params_sp[["rules"]]) &&
      !is.null(params_sp[["rules"]][["spawn"]])) {
    csv_thresholds_spawn <- list(
      gradient = c(sp_params$spawn_gradient_min,
                   sp_params$spawn_gradient_max),
      channel_width = params_sp$ranges$spawn$channel_width)
    spawn_pred <- .frs_rules_to_sql(params_sp[["rules"]][["spawn"]],
                                    csv_thresholds_spawn)
  } else {
    spawn_pred <- sprintf("s.gradient >= %s AND s.gradient <= %s",
      .frs_sql_num(sp_params$spawn_gradient_min),
      .frs_sql_num(sp_params$spawn_gradient_max))
    if (!is.null(params_sp$ranges$spawn$channel_width)) {
      cw <- params_sp$ranges$spawn$channel_width
      spawn_pred <- paste0(spawn_pred, sprintf(
        " AND s.channel_width >= %s AND s.channel_width <= %s",
        .frs_sql_num(cw[1]), .frs_sql_num(cw[2])))
    }
    spawn_et <- edge_filter(params_sp$spawn_edge_types)
    if (!is.null(spawn_et)) {
      spawn_pred <- paste(spawn_pred, "AND", spawn_et)
    }
  }

  # --- rear predicate ---
  if (!is.null(params_sp[["rules"]]) &&
      !is.null(params_sp[["rules"]][["rear"]])) {
    rear_g <- params_sp$ranges$rear$gradient
    csv_thresholds_rear <- list(
      gradient = if (is.null(rear_g)) NULL else c(0, rear_g[2]),
      channel_width = params_sp$ranges$rear$channel_width)
    rear_pred <- .frs_rules_to_sql(params_sp[["rules"]][["rear"]],
                                   csv_thresholds_rear)
  } else {
    rear_pred <- "FALSE"
    if (!is.null(params_sp$ranges$rear)) {
      parts <- character(0)
      if (!is.null(params_sp$ranges$rear$gradient)) {
        g <- params_sp$ranges$rear$gradient
        parts <- c(parts, sprintf("s.gradient <= %s",
                                  .frs_sql_num(g[2])))
      }
      if (!is.null(params_sp$ranges$rear$channel_width)) {
        cw <- params_sp$ranges$rear$channel_width
        parts <- c(parts, sprintf(
          "s.channel_width >= %s AND s.channel_width <= %s",
          .frs_sql_num(cw[1]), .frs_sql_num(cw[2])))
      }
      rear_et <- edge_filter(params_sp$rear_edge_types)
      if (!is.null(rear_et)) parts <- c(parts, rear_et)
      if (length(parts) > 0) rear_pred <- paste(parts, collapse = " AND ")
    }
  }

  # --- lake_rear / wetland_rear predicates ---
  # Gated on presence of waterbody_type: L / W rule in rear rules.
  # Without the rule, predicate is FALSE — species not lake/wetland rearing.
  build_wb_pred <- function(rule, ha_key, poly_table) {
    if (is.null(rule) || is.null(params_sp$ranges$rear$channel_width)) {
      return("FALSE")
    }
    cw <- params_sp$ranges$rear$channel_width
    ha_min <- rule[[ha_key]]
    area_clause <- if (!is.null(ha_min) && !is.na(ha_min)) {
      sprintf(" WHERE area_ha >= %s", .frs_sql_num(ha_min))
    } else {
      ""
    }
    sprintf(
      "s.channel_width >= %s AND s.channel_width <= %s
       AND s.waterbody_key IN (
         SELECT waterbody_key FROM %s%s)",
      .frs_sql_num(cw[1]), .frs_sql_num(cw[2]),
      poly_table, area_clause)
  }

  lake_rule    <- .frs_find_waterbody_rule(params_sp[["rules"]][["rear"]], "L")
  wetland_rule <- .frs_find_waterbody_rule(params_sp[["rules"]][["rear"]], "W")

  lake_rear_pred    <- build_wb_pred(lake_rule, "lake_ha_min",
                                     "whse_basemapping.fwa_lakes_poly")
  wetland_rear_pred <- build_wb_pred(wetland_rule, "wetland_ha_min",
                                     "whse_basemapping.fwa_wetlands_poly")

  list(
    spawn        = spawn_pred,
    rear         = rear_pred,
    lake_rear    = lake_rear_pred,
    wetland_rear = wetland_rear_pred
  )
}
