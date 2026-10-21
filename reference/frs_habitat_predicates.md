# Build SQL predicates for one species' habitat classification

Pure-R helper: takes one species' rules + ranges from
[`frs_params()`](https://newgraphenvironment.github.io/fresh/reference/frs_params.md)
and returns a named list of SQL boolean expressions ("predicates") — the
raw yes/no questions that
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
embeds in `CASE WHEN <pred> THEN TRUE ...` to produce the per-species
habitat columns.

## Usage

``` r
frs_habitat_predicates(sp_params, model = "cw", near_river_table = NULL)
```

## Arguments

- sp_params:

  A single-species list with `species_code`, `spawn_gradient_min`,
  `spawn_gradient_max`, and `params_sp`: that species' element of
  [`frs_params()`](https://newgraphenvironment.github.io/fresh/reference/frs_params.md)
  (its `ranges`, optional `rules`, optional `spawn_edge_types` /
  `rear_edge_types`). This is the shape
  [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  builds per species.

- model:

  Character. Habitat size model: `"cw"` (channel width, default) or
  `"mad"` (mean annual discharge, `mad_m3s`).

- near_river_table:

  Character or `NULL`. Schema-qualified table of distances to the
  nearest river downstream, as written by
  [`frs_near_river()`](https://newgraphenvironment.github.io/fresh/reference/frs_near_river.md).
  Required when a spawn or rear rule carries `near_river`;
  [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  builds it and passes it. A rule matches only rows walked at exactly
  its own `discharge_min` and `distance_max`.

## Value

A named list with four character scalars: `spawn`, `rear`, `lake_rear`,
`wetland_rear`. Each is an SQL boolean expression suitable for embedding
in `CASE WHEN ... THEN TRUE ELSE FALSE END`. Predicates reference the
segmented streams alias `s.`.

## Details

Returns four predicates per call: `spawn`, `rear`, `lake_rear`,
`wetland_rear`. Each is a fragment that references columns aliased as
`s.` (the segmented streams table). Caller is responsible for embedding
them in a complete query.

Two paths are supported, selected per habitat type by what's present in
`sp_params`:

1.  **Rules path** — when `sp_params$params_sp$rules$<spawn|rear>` is
    non-NULL, the rules YAML is compiled to SQL via
    `.frs_rules_to_sql()`. CSV thresholds (gradient + the `model`'s size
    dimension) are passed as the inheritance fallback for rules that
    omit explicit thresholds.

2.  **CSV-ranges path** — pre-rules behaviour. Builds the SQL directly
    from `sp_params$params_sp$ranges` +
    `sp_params$params_sp$<spawn|rear>_edge_types`.

`model` picks the size dimension, mirroring bcfishpass
`parameters_habitat_method.csv`. `"cw"` (default) uses the CSV
channel-width ranges (`ranges$<spawn|rear>$channel_width`). `"mad"` uses
the CSV mean annual discharge ranges (`ranges$<spawn|rear>$mad_m3s`)
against `s.mad_m3s` instead, on both paths. Under `"mad"`, matching
bcfishpass: a species with no MAD thresholds (e.g. BT) gets no stream
spawning / rearing from inheriting rules; segments with NULL `mad_m3s`
fail; and rule-level `channel_width:` (the cw-model river-polygon
bypass) is ignored. An explicit `mad: [min, max]` rule applies under
either model.
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
resolves the model per watershed group.

**A river nearby (`near_river`).** A spawn or rear rule can carry

    near_river:
      discharge_min: 3     # m3/s
      distance_max: 1000   # m, along the network, downstream

The segment then passes the rule's size test (channel width under `cw`,
`mad_m3s` under `mad`, inherited or explicit) **or** a segment carrying
at least `discharge_min` lies within `distance_max` downstream.
Everything else in the rule (edge types, gradient, waterbody tests)
still applies. The distance is measured by
[`frs_near_river()`](https://newgraphenvironment.github.io/fresh/reference/frs_near_river.md),
which
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
runs and passes as `near_river_table`:

- from the segment's downstream end, so a long segment whose lower end
  is within reach passes whole;

- to the river's bank: a tributary's connector line across the river's
  polygon is left out, and never counts as the river;

- only for segments whose own `mad_m3s` is NULL or below
  `discharge_min`: a river that large passes or fails on its own size
  test;

- within one watershed group's table, and never from a segment with no
  local watershed code (most side channels); see
  [`frs_near_river()`](https://newgraphenvironment.github.io/fresh/reference/frs_near_river.md).

Two consequences to know. A rule with no size test of its own (a
`thresholds: false` rule without `channel_width` or `mad`) makes
`near_river` its only size test, and such a rule inherits **no
gradient**, so it tests slope only if it carries `gradient:`. Under
`mad`, a species with no MAD range, which otherwise gets no stream
habitat from inheriting rules, qualifies through `near_river` where a
river is near. `near_river` is not allowed on `waterbody_type: L` or `W`
rules.

Lake / wetland rearing predicates (`lake_rear`, `wetland_rear`) are
gated on the presence of a `waterbody_type: L` / `waterbody_type: W`
rule in `rear:`. Without the rule, the predicate is `"FALSE"` — the
species is not lake or wetland-rearing. With the rule, the predicate is
polygon membership, filtered by the rule's optional `lake_ha_min` /
`wetland_ha_min`. It carries no channel-width or discharge test under
either model: the line through a polygon measures its inflow, not the
polygon. Connection to spawning is applied after classification, for
rules that carry `requires_connected: spawning` (see
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)).

## See also

Other habitat:
[`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
[`frs_categorize()`](https://newgraphenvironment.github.io/fresh/reference/frs_categorize.md),
[`frs_channel_width()`](https://newgraphenvironment.github.io/fresh/reference/frs_channel_width.md),
[`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md),
[`frs_cluster()`](https://newgraphenvironment.github.io/fresh/reference/frs_cluster.md),
[`frs_col_generate()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_generate.md),
[`frs_col_join()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_join.md),
[`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md),
[`frs_feature_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_find.md),
[`frs_feature_index()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_index.md),
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md),
[`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md),
[`frs_habitat_overlay()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md),
[`frs_near_river()`](https://newgraphenvironment.github.io/fresh/reference/frs_near_river.md),
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
params <- frs_params(csv = system.file("extdata",
  "parameters_habitat_thresholds.csv", package = "fresh"))
sp_params <- list(species_code = "CO",
  spawn_gradient_min = 0,
  spawn_gradient_max = params$CO$spawn_gradient_max,
  params_sp = params$CO)

preds <- frs_habitat_predicates(sp_params)
preds$spawn
#> [1] "((s.edge_type IN (1000, 1100, 2000, 2300) AND s.waterbody_key IS NULL AND s.gradient BETWEEN 0 AND 0.0549 AND s.channel_width BETWEEN 2 AND 9999) OR (s.waterbody_key IN (SELECT waterbody_key FROM whse_basemapping.fwa_rivers_poly) AND s.gradient BETWEEN 0 AND 0.0549 AND s.channel_width BETWEEN 0 AND 9999))"
preds$lake_rear
#> [1] "s.waterbody_key IN (\n         SELECT waterbody_key FROM whse_basemapping.fwa_lakes_poly WHERE area_ha >= 2)"

# Discharge-based model, as for a `mad` watershed group
frs_habitat_predicates(sp_params, model = "mad")$spawn
#> [1] "((s.edge_type IN (1000, 1100, 2000, 2300) AND s.waterbody_key IS NULL AND s.gradient BETWEEN 0 AND 0.0549 AND s.mad_m3s BETWEEN 0.164 AND 9999) OR (s.waterbody_key IN (SELECT waterbody_key FROM whse_basemapping.fwa_rivers_poly) AND s.gradient BETWEEN 0 AND 0.0549 AND s.mad_m3s BETWEEN 0.164 AND 9999))"

# A small stream passes when a 3 m3/s river is within 1 km downstream
sp_params$params_sp$rules$rear <- list(list(
  edge_types_explicit = c(1000, 1100),
  near_river = list(discharge_min = 3, distance_max = 1000)))
frs_habitat_predicates(sp_params,
  near_river_table = "working.streams_habitat_near_river")$rear
#> [1] "((s.edge_type IN (1000, 1100) AND s.gradient BETWEEN 0 AND 0.0549 AND (s.channel_width BETWEEN 1.5 AND 9999 OR EXISTS (SELECT 1 FROM working.streams_habitat_near_river n WHERE n.id_segment = s.id_segment AND n.watershed_group_code = s.watershed_group_code AND n.discharge_min = 3 AND n.distance_max = 1000 AND n.dist_m <= 1000))))"
```
