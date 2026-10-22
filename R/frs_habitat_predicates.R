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
#' **A river nearby (`near_river`).** A segment can pass a rule's size
#' test (channel width under `cw`, `mad_m3s` under `mad`, inherited or
#' explicit) **or** lie within a distance downstream of a river. "A
#' river" is a segment at least some size by one of three measures:
#' discharge (`mad_m3s`), modelled channel width or stream order. A rule
#' gets the condition in one of two ways:
#'
#' - **Inherited from the thresholds CSV**, per stage, beside its
#'   gradient, width and MAD ranges: `<stage>_river_measure`
#'   (`discharge`, `channel_width`, `stream_order`, or `model`, which
#'   reads width under `cw` and discharge under `mad`; absent is
#'   `model`), the threshold of each measure
#'   (`<stage>_river_discharge_min`, `<stage>_river_channel_width_min`,
#'   `<stage>_river_stream_order_min`) and `<stage>_river_distance_max`
#'   (m). [frs_params()] stores the pair as `params[[sp]]$near_river`.
#'   Every rule that inherits thresholds **and has a size test** takes
#'   it. A rule with no size test (under `cw`, one whose stage has no
#'   width range) does not, because the pair would then be its only size
#'   test and tighten it. A `waterbody_type: R` rule inherits like a
#'   stream rule: with the bundled `channel_width: [0, 9999]` that admits
#'   a river line with no width that lies near a bigger river, so a
#'   consumer that means "the river polygon is the river" sets
#'   `near_river: false` on it.
#' - **On the rule**, overriding what it would inherit:
#'
#'   ```yaml
#'   near_river:
#'     discharge_min: 3     # or channel_width_min (m) or stream_order_min
#'     distance_max: 1000   # m, along the network, downstream
#'   ```
#'
#'   or `near_river: false` to opt out of an inherited pair (a no-op on a
#'   `thresholds: false` rule, which inherits nothing).
#'
#' The size test becomes `(<size> OR EXISTS ...)`; everything else in the
#' rule (edge types, gradient, waterbody tests) still applies. The
#' distance is measured by [frs_near_river()], which
#' [frs_habitat_classify()] runs and passes as `near_river_table`:
#' - from the segment's downstream end, so a long segment whose lower end
#'   is within reach passes whole;
#' - to the river's bank: a tributary's connector line across the river's
#'   polygon is left out, and never counts as the river;
#' - only for segments smaller than the threshold by the same measure: a
#'   river that large passes or fails on its own size test;
#' - within one watershed group's table, and never from a segment with no
#'   local watershed code (most side channels); see [frs_near_river()].
#'
#' Two consequences to know. A `thresholds: false` rule with its own
#' mapping and no `channel_width` or `mad` has `near_river` as its only
#' size test, and inherits **no gradient**, so it tests slope only if it
#' carries `gradient:`. Under `mad`, a species with no MAD range, which
#' otherwise gets no stream habitat from inheriting rules, qualifies
#' through `near_river` where a river is near. `near_river` (a mapping or
#' `false`) is not allowed on `waterbody_type: L` or `W` rules. Species
#' with no rules compile from `ranges` directly and get no pair.
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
#' @param near_river_table Character or `NULL`. Schema-qualified table of
#'   distances to the nearest river downstream, as written by
#'   [frs_near_river()]. Required when a spawn or rear rule has a
#'   `near_river` pair, its own or inherited; [frs_habitat_classify()]
#'   builds it and passes it. A rule matches only rows walked at exactly
#'   its own measure, threshold and `distance_max`.
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
#'
#' # A small stream passes when a 3 m3/s river is within 1 km downstream
#' sp_params$params_sp$rules$rear <- list(list(
#'   edge_types_explicit = c(1000, 1100),
#'   near_river = list(discharge_min = 3, distance_max = 1000)))
#' frs_habitat_predicates(sp_params,
#'   near_river_table = "working.streams_habitat_near_river")$rear
#'
#' # The same rule with no mapping inherits the stage's pair from the
#' # thresholds CSV (here a 20 m channel within 1 km, under cw)
#' sp_params$params_sp$rules$rear[[1]]$near_river <- NULL
#' sp_params$params_sp$near_river$rear <- list(measure = "channel_width",
#'   channel_width_min = 20, distance_max = 1000)
#' frs_habitat_predicates(sp_params,
#'   near_river_table = "working.streams_habitat_near_river")$rear
frs_habitat_predicates <- function(sp_params, model = "cw",
                                   near_river_table = NULL) {
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
  size_sql <- function(rng) {
    if (is.null(rng)) return(if (model == "mad") "FALSE" else NULL)
    sprintf("s.%s >= %s AND s.%s <= %s",
      size_col, .frs_sql_num(rng[1]), size_col, .frs_sql_num(rng[2]))
  }

  # --- spawn predicate ---
  if (!is.null(params_sp[["rules"]]) &&
      !is.null(params_sp[["rules"]][["spawn"]])) {
    csv_thresholds_spawn <- c(
      list(gradient = c(sp_params$spawn_gradient_min,
                        sp_params$spawn_gradient_max)),
      .frs_stage_inherit(params_sp, "spawn", model))
    spawn_pred <- .frs_rules_to_sql(
      .frs_stage_rules(params_sp, "spawn", model), csv_thresholds_spawn,
      near_river_table = near_river_table)
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
    csv_thresholds_rear <- c(
      list(gradient = if (is.null(rear_g)) NULL else c(0, rear_g[2])),
      .frs_stage_inherit(params_sp, "rear", model))
    rear_pred <- .frs_rules_to_sql(.frs_stage_rules(params_sp, "rear", model),
                                   csv_thresholds_rear,
                                   near_river_table = near_river_table)
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


#' The rules one stage compiles, for one size model
#'
#' A stage's rules as the main predicate compiles them. On `rear`, rules
#' flagged `area_only: true` are dropped: they drive the lake / wetland
#' bucket flags only, and `.frs_find_waterbody_rule()` still finds them.
#' Under `mad`, a rule-level `channel_width:` is dropped: it is a
#' cw-model construct (the bundled `waterbody_type: R` rules use it as
#' the river-polygon bypass), bcfishpass's mad branch has no such bypass,
#' and the rule then inherits the MAD range like any other.
#'
#' @param params_sp One species' element of [frs_params()].
#' @param stage `"spawn"` or `"rear"`.
#' @param model `"cw"` or `"mad"`.
#' @return A list of rules, possibly empty; `NULL` when the species has
#'   no rules for the stage.
#' @noRd
.frs_stage_rules <- function(params_sp, stage, model) {
  rules <- params_sp[["rules"]][[stage]]
  if (is.null(rules)) return(NULL)
  if (stage == "rear") rules <- Filter(function(r) !isTRUE(r[["area_only"]]),
                                       rules)
  if (model != "mad") return(rules)
  lapply(rules, function(r) {
    r[["channel_width"]] <- NULL
    r
  })
}


#' What a stage's rules inherit from the thresholds CSV, besides gradient
#'
#' The size range of the model (`channel_width` under `cw`, `mad_m3s`
#' under `mad`, where a species with no MAD range gets `c(NA, NA)`, which
#' makes inheriting rules match nothing) and the stage's near_river pair
#' resolved for the model (#263). It is not a size column, so it goes in
#' under both models.
#'
#' @inheritParams .frs_stage_rules
#' @return A named list holding whichever of the two is set.
#' @noRd
.frs_stage_inherit <- function(params_sp, stage, model) {
  size_col <- if (model == "mad") "mad_m3s" else "channel_width"
  out <- list()
  rng <- params_sp$ranges[[stage]][[size_col]]
  if (is.null(rng) && model == "mad") rng <- c(NA_real_, NA_real_)
  out[[size_col]] <- rng
  out[["near_river"]] <- .frs_near_river_resolve(
    params_sp[["near_river"]][[stage]], model)
  out
}


#' Distinct near_river pairs a set of species' rules ask for
#'
#' Collects every spawn and rear rule's effective pair
#' (`.frs_rule_near_river()`, the compiler's own resolver: an explicit
#' mapping, or the stage's inherited pair, never a `near_river: false`)
#' under each size model in `models`, and returns one row per distinct
#' `(measure, threshold, distance_max)`. [frs_near_river()] walks once
#' per pair, so one rule's answer never depends on another rule's.
#'
#' @param params Named list from [frs_params()].
#' @param species Character vector of species codes.
#' @param models Character. The size models predicates are built for
#'   (`"cw"`, `"mad"`); a `model` measure resolves per model.
#' @return A data frame with character `measure` and numeric `threshold`
#'   and `distance_max`, ordered by all three; zero rows when no rule
#'   asks.
#' @noRd
.frs_near_river_specs <- function(params, species, models = "cw") {
  nrs <- list()
  for (sp in species) {
    params_sp <- params[[sp]]
    for (model in unique(models)) {
      for (stage in c("spawn", "rear")) {
        rules <- .frs_stage_rules(params_sp, stage, model)
        csv <- .frs_stage_inherit(params_sp, stage, model)
        for (r in rules) {
          nr <- .frs_rule_near_river(r, csv)
          if (!is.null(nr)) nrs[[length(nrs) + 1L]] <- nr
        }
      }
    }
  }
  .frs_near_river_specs_frame(nrs)
}


#' One row per distinct near_river pair, ordered
#'
#' @param nrs List of stored-form near_river mappings.
#' @noRd
.frs_near_river_specs_frame <- function(nrs) {
  if (length(nrs) == 0) {
    return(data.frame(measure = character(0), threshold = numeric(0),
                      distance_max = numeric(0), stringsAsFactors = FALSE))
  }
  out <- unique(data.frame(
    measure = vapply(nrs, function(x) x[["measure"]], character(1)),
    threshold = vapply(nrs, function(x) x[["threshold"]], numeric(1)),
    distance_max = vapply(nrs, function(x) x[["distance_max"]], numeric(1)),
    stringsAsFactors = FALSE))
  out <- out[order(out$measure, out$threshold, out$distance_max), ,
             drop = FALSE]
  rownames(out) <- NULL
  out
}
