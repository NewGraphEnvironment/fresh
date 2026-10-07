#' Build SQL predicates for one species' habitat classification
#'
#' Pure-R helper: takes one species' rules + ranges from [frs_params()]
#' and returns a named list of SQL boolean
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
#' 1. **Rules path** — when `sp_params$params_sp$rules$<spawn|rear>` is
#'    non-NULL,
#'    the rules YAML is compiled to SQL via `.frs_rules_to_sql()`.
#'    CSV thresholds (gradient + the `model`'s size dimension) are passed
#'    as the inheritance fallback for rules that omit explicit thresholds.
#' 2. **CSV-ranges path** — pre-rules behaviour. Builds the SQL
#'    directly from `sp_params$params_sp$ranges` +
#'    `sp_params$params_sp$<spawn|rear>_edge_types`.
#'
#' `model` picks the size dimension, mirroring bcfishpass
#' `parameters_habitat_method.csv`. `"cw"` (default) uses the CSV
#' channel-width ranges (`ranges$<spawn|rear>$channel_width`). `"mad"`
#' uses the CSV mean annual discharge ranges (`ranges$<spawn|rear>$mad_m3s`)
#' against `s.mad_m3s` instead, on both paths. Under `"mad"`, matching
#' bcfishpass: a species with no MAD thresholds (e.g. BT) gets no stream
#' spawning / rearing from inheriting rules; segments with NULL `mad_m3s`
#' fail; and rule-level `channel_width:` (the cw-model river-polygon
#' bypass) is ignored. An explicit `mad: [min, max]` rule applies under
#' either model. [frs_habitat_classify()] resolves the model per
#' watershed group.
#'
#' Lake / wetland rearing predicates (`lake_rear`, `wetland_rear`) are
#' gated on the presence of a `waterbody_type: L` / `waterbody_type: W`
#' rule in `rear:`. Without the rule, the predicate is `"FALSE"` — the
#' species is not lake or wetland-rearing. With the rule, the predicate
#' is polygon membership, filtered by the rule's optional `lake_ha_min` /
#' `wetland_ha_min`. It carries no channel-width or discharge test under
#' either model: the line through a polygon measures its inflow, not the
#' polygon. Connection to spawning is applied after classification, for
#' rules that carry `requires_connected: spawning` (see [frs_habitat()]).
#'
#' @param sp_params A single-species list with `species_code`,
#'   `spawn_gradient_min`, `spawn_gradient_max`, and `params_sp`: that
#'   species' element of [frs_params()] (its `ranges`, optional `rules`,
#'   optional `spawn_edge_types` / `rear_edge_types`). This is the shape
#'   [frs_habitat_classify()] builds per species.
#' @param model Character. Habitat size model: `"cw"` (channel width,
#'   default) or `"mad"` (mean annual discharge, `mad_m3s`).
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
#' params <- frs_params(csv = system.file("extdata",
#'   "parameters_habitat_thresholds.csv", package = "fresh"))
#' sp_params <- list(species_code = "CO",
#'   spawn_gradient_min = 0,
#'   spawn_gradient_max = params$CO$spawn_gradient_max,
#'   params_sp = params$CO)
#'
#' preds <- frs_habitat_predicates(sp_params)
#' preds$spawn
#' preds$lake_rear
#'
#' # Discharge-based model, as for a `mad` watershed group
#' frs_habitat_predicates(sp_params, model = "mad")$spawn
frs_habitat_predicates <- function(sp_params, model = "cw") {
  stopifnot(is.list(sp_params),
            !is.null(sp_params[["species_code"]]))
  if (!is.character(model) || length(model) != 1L ||
      !model %in% c("cw", "mad")) {
    stop('model must be "cw" or "mad"', call. = FALSE)
  }

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

  # Size dimension: channel width (cw model) or mean annual discharge
  # (mad model). Under mad, a species without MAD thresholds gets a NA
  # range for rules-path inheritance and a FALSE size predicate on the
  # CSV path — nothing qualifies (bcfishpass parity).
  size_col <- if (model == "mad") "mad_m3s" else "channel_width"
  size_spawn <- params_sp$ranges$spawn[[size_col]]
  size_rear  <- params_sp$ranges$rear[[size_col]]
  size_inherit <- function(rng) {
    if (is.null(rng) && model == "mad") c(NA_real_, NA_real_) else rng
  }
  size_sql <- function(rng) {
    if (is.null(rng)) return(if (model == "mad") "FALSE" else NULL)
    sprintf("s.%s >= %s AND s.%s <= %s",
      size_col, .frs_sql_num(rng[1]), size_col, .frs_sql_num(rng[2]))
  }
  # Rule-level `channel_width:` is a cw-model construct (the bundled
  # `waterbody_type: R` rules use it as the river-polygon bypass).
  # bcfishpass's mad branch has no such bypass, so drop it under mad and
  # let the rule inherit the MAD range like any other.
  model_rules <- function(rules) {
    if (model != "mad") return(rules)
    lapply(rules, function(r) {
      r[["channel_width"]] <- NULL
      r
    })
  }

  # --- spawn predicate ---
  if (!is.null(params_sp[["rules"]]) &&
      !is.null(params_sp[["rules"]][["spawn"]])) {
    csv_thresholds_spawn <- list(
      gradient = c(sp_params$spawn_gradient_min,
                   sp_params$spawn_gradient_max))
    csv_thresholds_spawn[[size_col]] <- size_inherit(size_spawn)
    spawn_pred <- .frs_rules_to_sql(
      model_rules(params_sp[["rules"]][["spawn"]]), csv_thresholds_spawn)
  } else {
    spawn_pred <- sprintf("s.gradient >= %s AND s.gradient <= %s",
      .frs_sql_num(sp_params$spawn_gradient_min),
      .frs_sql_num(sp_params$spawn_gradient_max))
    spawn_size <- size_sql(size_spawn)
    if (!is.null(spawn_size)) {
      spawn_pred <- paste(spawn_pred, "AND", spawn_size)
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
      gradient = if (is.null(rear_g)) NULL else c(0, rear_g[2]))
    csv_thresholds_rear[[size_col]] <- size_inherit(size_rear)
    # Filter out rules flagged `area_only: true` — those rules drive
    # lake_rearing / wetland_rearing bucket-flag derivation only and
    # should not contribute to the main `rear` predicate. The bucket
    # rule lookup below still finds them via .frs_find_waterbody_rule().
    rear_rules_for_main <- Filter(
      function(r) !isTRUE(r[["area_only"]]),
      params_sp[["rules"]][["rear"]])
    rear_pred <- .frs_rules_to_sql(model_rules(rear_rules_for_main),
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
      parts <- c(parts, size_sql(size_rear))
      rear_et <- edge_filter(params_sp$rear_edge_types)
      if (!is.null(rear_et)) parts <- c(parts, rear_et)
      if (length(parts) > 0) rear_pred <- paste(parts, collapse = " AND ")
    }
  }

  # --- lake_rear / wetland_rear predicates ---
  # Gated on presence of waterbody_type: L / W rule in rear rules.
  # Without the rule, predicate is FALSE — species not lake/wetland rearing.
  # With it, polygon membership and area only, under either model: a
  # stream-size test on the line through the polygon sizes its inflow,
  # not the polygon (fresh#240; bcfishpass sizes lakes by area alone).
  # The floor comes from .frs_rule_ha_min(), the same reader the main
  # `rear` predicate uses, so the two can't disagree (fresh#237).
  build_wb_pred <- function(rule, poly_table) {
    if (is.null(rule)) return("FALSE")
    ha_min <- .frs_rule_ha_min(rule)
    area_clause <- if (is.null(ha_min)) "" else
      sprintf(" WHERE area_ha >= %s", .frs_sql_num(ha_min))
    sprintf("s.waterbody_key IN (
         SELECT waterbody_key FROM %s%s)", poly_table, area_clause)
  }

  lake_rule    <- .frs_find_waterbody_rule(params_sp[["rules"]][["rear"]], "L")
  wetland_rule <- .frs_find_waterbody_rule(params_sp[["rules"]][["rear"]], "W")

  lake_rear_pred    <- build_wb_pred(lake_rule,
                                     "whse_basemapping.fwa_lakes_poly")
  wetland_rear_pred <- build_wb_pred(wetland_rule,
                                     "whse_basemapping.fwa_wetlands_poly")

  list(
    spawn        = spawn_pred,
    rear         = rear_pred,
    lake_rear    = lake_rear_pred,
    wetland_rear = wetland_rear_pred
  )
}
