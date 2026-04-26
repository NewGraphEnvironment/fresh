# Build SQL predicates for one species' habitat classification

Pure-R helper: takes one species' rules + ranges from
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md)
and returns a named list of SQL boolean expressions ("predicates") — the
raw yes/no questions that
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
embeds in `CASE WHEN <pred> THEN TRUE ...` to produce the per-species
habitat columns.

## Usage

``` r
frs_habitat_predicates(sp_params)
```

## Arguments

- sp_params:

  A single-species params list as produced by one element of
  [`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md).
  Must contain `species_code`, `spawn_gradient_min`,
  `spawn_gradient_max`, `ranges`, optionally `rules`, optionally
  `spawn_edge_types` / `rear_edge_types`.

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

1.  **Rules path** — when `sp_params$rules$<spawn|rear>` is non-NULL,
    the rules YAML is compiled to SQL via `.frs_rules_to_sql()`. CSV
    thresholds (gradient + channel_width) are passed as the inheritance
    fallback for rules that omit explicit thresholds.

2.  **CSV-ranges path** — pre-rules behaviour. Builds the SQL directly
    from `sp_params$ranges` + `sp_params$<spawn|rear>_edge_types`.

Lake / wetland rearing predicates are gated on the presence of a
`waterbody_type: L` / `waterbody_type: W` rule in `rear:`. Without the
rule, the predicate is `"FALSE"` — the species is not lake or
wetland-rearing. With the rule, an optional `lake_ha_min` /
`wetland_ha_min` filters the polygon join.

Segments must still fall within the species' rear channel-width window
for lake / wetland rearing.

## See also

Other habitat:
[`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
[`frs_categorize()`](https://newgraphenvironment.github.io/fresh/reference/frs_categorize.md),
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
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
if (FALSE) { # \dontrun{
params <- frs_params()
params_fresh <- read.csv(system.file("extdata",
  "parameters_fresh.csv", package = "fresh"))
species_params <- frs_habitat_species("CO", params, params_fresh)

preds <- frs_habitat_predicates(species_params[[1]])
preds$spawn
#> "s.gradient >= 0 AND s.gradient <= 0.0549 AND ..."
preds$lake_rear
#> "FALSE"  (CO has no waterbody_type: L rule under bcfishpass)
} # }
```
