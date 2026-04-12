# Changelog

## fresh 0.13.2

Preserve multiple labels per break position.

- Multiple labels at the same
  `(blue_line_key, downstream_route_measure)` now survive in
  `streams_breaks` — a gradient_15 and a falls at the same measure are
  both preserved. Enables per-barrier overrides, access reporting, and
  habitat reporting by barrier type
  ([\#145](https://github.com/NewGraphEnvironment/fresh/issues/145))

## fresh 0.13.1

Persist gradient barriers and downstream-only distance fix.

- `to_barriers` parameter on
  [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
  — persist gradient barriers table with ltree enrichment for link’s
  `lnk_barrier_overrides()`
  ([\#143](https://github.com/NewGraphEnvironment/fresh/issues/143))
- `connected_distance_max` distance filter now downstream-only with
  correct `fwa_upstream` direction
  ([\#133](https://github.com/NewGraphEnvironment/fresh/issues/133))
- Fix `aoi` + `wsg` interaction — character aoi ANDed with WSG filter
  instead of replacing it
  ([\#141](https://github.com/NewGraphEnvironment/fresh/issues/141))

## fresh 0.13.0

Distance filter, aoi fix, and measure rounding.

- `connected_distance_max` distance filter now downstream-only —
  upstream spawning has no distance cap, matching bcfishpass v0.5.0 SK
  spawning logic. Uses DRM difference (same-BLK) and ST_Distance
  Euclidean (cross-BLK)
  ([\#133](https://github.com/NewGraphEnvironment/fresh/issues/133))
- Fix `aoi` replacing `wsg` filter instead of being additive —
  `frs_habitat(wsg = "ADMS", aoi = "edge_type != 6010")` now correctly
  scopes to ADMS, not province-wide
  ([\#141](https://github.com/NewGraphEnvironment/fresh/issues/141))
- `measure_precision` parameter on
  [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)
  and
  [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
  — controls break measure rounding. Default `0` (integer, matching
  bcfishpass). Breaks table rounded and deduped before splitting
  ([\#135](https://github.com/NewGraphEnvironment/fresh/issues/135))
- Auto-skip gradient/channel_width inheritance on
  `waterbody_type: L`/`W` rules
  ([\#131](https://github.com/NewGraphEnvironment/fresh/issues/131))

## fresh 0.12.9

Post-cluster distance filter, measure rounding, and lake threshold
auto-skip.

- `connected_distance_max` now caps habitat EXTENT from connected
  segments (not just search distance). Post-cluster filter removes
  individual segments beyond the cap. SK spawning 112 km → ~74 km
  ([\#133](https://github.com/NewGraphEnvironment/fresh/issues/133))
- `measure_precision` parameter on
  [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)
  and
  [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
  — controls decimal places for break measure rounding. Default `0`
  (integer, matching bcfishpass). Breaks table rounded and deduped
  before splitting
  ([\#135](https://github.com/NewGraphEnvironment/fresh/issues/135))
- Auto-skip gradient/channel_width inheritance on
  `waterbody_type: L`/`W` rules — lake/wetland flow lines are routing
  lines
  ([\#131](https://github.com/NewGraphEnvironment/fresh/issues/131))

## fresh 0.12.8

Lake/wetland threshold auto-skip and connected distance cap.

- Auto-skip gradient/channel_width CSV inheritance on
  `waterbody_type: L` and `waterbody_type: W` rules — lake/wetland flow
  lines are routing lines, channel dimensions are meaningless
  ([\#131](https://github.com/NewGraphEnvironment/fresh/issues/131))
- `connected_distance_max` predicate in rules YAML — caps network
  distance from connected habitat when `requires_connected` is present.
  SK/KO spawning capped at 3km from rearing lake
  ([\#133](https://github.com/NewGraphEnvironment/fresh/issues/133))

## fresh 0.12.7

Replace observations with barrier_overrides.

- `barrier_overrides` parameter replaces `observations` on
  [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
  and
  [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  — accepts a pre-computed table of
  `(blue_line_key, downstream_route_measure, species_code)` from link.
  Fresh skips matched barriers without counting, thresholds, or date
  filters
  ([\#129](https://github.com/NewGraphEnvironment/fresh/issues/129))
- Remove observation counting SQL and `observation_*` columns from
  `parameters_fresh.csv` — fish passage interpretation belongs in link,
  not the network engine

## fresh 0.12.6

Multi-class gradient barrier detection.

- `frs_break_find(classes =)` — single-pass multi-class gradient
  detection matching bcfishpass v0.5.0. Tags every vertex with its
  gradient class, groups consecutive same-class vertices into islands,
  places one barrier at each class transition. Catches transitions
  WITHIN steep sections that boolean above/below missed
  ([\#127](https://github.com/NewGraphEnvironment/fresh/issues/127))
- `frs_break_find(blk_filter =)` — restrict to main flow lines
  (`blue_line_key = watershed_key`). Default TRUE (matches bcfishpass)
- [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
  now calls
  [`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md)
  once with all gradient classes instead of looping per threshold.
  Simpler, faster, more barriers detected.

## fresh 0.12.5

Observation-based access override.

- `observations` parameter on
  [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
  and
  [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  — fish observations upstream of gradient/falls barriers override
  access gating per species. Thresholds from `parameters_fresh.csv`:
  `observation_threshold`, `observation_date_min`,
  `observation_buffer_m`, `observation_species`
  ([\#69](https://github.com/NewGraphEnvironment/fresh/issues/69))
- Defaults match bcfishpass v0.5.0: BT \>= 1 obs (all salmonids count),
  CH/CO/SK/PK/CM/ST \>= 5 obs (species-specific), since 1990, 20m buffer
- ADMS: BT accessible +103%, CH/CO +10% with `bcfishobs.observations`

## fresh 0.12.4

Post-segmentation gradient control.

- `gradient_recompute` parameter on
  [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)
  and
  [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
  — `TRUE` (default) recomputes gradient from DEM vertices after
  splitting; `FALSE` inherits parent segment gradient, matching
  bcfishpass v0.5.0 behavior
  ([\#124](https://github.com/NewGraphEnvironment/fresh/issues/124))
- `frs_col_generate(exclude =)` — skip named columns from regeneration
  (generic, reusable)

## fresh 0.12.3

SK/KO spawning requires connected rearing lake.

- `requires_connected` predicate in rules YAML — spawning segments must
  be spatially connected to rearing via
  [`frs_cluster()`](https://newgraphenvironment.github.io/fresh/reference/frs_cluster.md).
  No rearing lake = no spawning
  ([\#120](https://github.com/NewGraphEnvironment/fresh/issues/120))
- New `.frs_run_connectivity()` orchestrates both rearing cluster checks
  (`cluster_rearing`) and spawning connectivity checks
  (`requires_connected` + `cluster_spawning`) after classification
- SK/KO: `cluster_spawning = TRUE` with 3km bridge distance. KO added to
  `parameters_fresh.csv`
- ADMS sub-basin: SK spawning 15 → 0 (correct — no lakes \>= 200 ha)

## fresh 0.12.2

Fix short barrier detection.

- [`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md)
  gains `min_length` parameter (default `0`) — keeps all gradient
  islands regardless of length. A 30m waterfall at 20% gradient is a
  real barrier but was silently dropped by the old 100m minimum. Pass
  `min_length = 100` to restore pre-0.12.2 behavior
  ([\#118](https://github.com/NewGraphEnvironment/fresh/issues/118))
- ADMS sub-basin at 15%: 137 barriers (was 98, +39 recovered)

## fresh 0.12.1

Per-rule threshold overrides in habitat rules YAML.

- Rules can now specify `gradient: [min, max]` and
  `channel_width: [min, max]` that override CSV inheritance per rule.
  Missing fields still inherit from CSV when `thresholds: true`
  ([\#116](https://github.com/NewGraphEnvironment/fresh/issues/116))
- Bundled YAML updated: all `waterbody_type: R` rules now have
  `channel_width: [0, 9999]` — skips channel_width_min on river polygons
  (matching bcfishpass v0.5.0 pattern where river polygon widths are
  unreliable)

## fresh 0.12.0

Habitat eligibility rules format (Phase 1).

- YAML-based habitat rules for multi-rule species — each species gets a
  list of rules per habitat type joined by OR, each rule is AND of
  predicates. Replaces the single-rule-per-CSV-row limitation
  ([\#113](https://github.com/NewGraphEnvironment/fresh/issues/113))
- Bundled `inst/extdata/parameters_habitat_rules.yaml` with NGE defaults
  for 11 species (synced from
  `link/inst/extdata/parameters_habitat_dimensions.csv`)
- `frs_params(rules_yaml =)` loads rules YAML (default = bundled, `NULL`
  = skip rules for backward compat)
- `frs_habitat(rules =)` pass-through (`NULL` = bundled, `FALSE` =
  disable, string path = custom file)
- `thresholds: false` per rule — wetland-flow carve-out pattern where a
  rule bypasses CSV gradient/channel_width inheritance
- **Default behavior change**: SK rearing now lake-only (area \>= 200
  ha); PK/CM rearing = 0 (explicit `rear: []`); CO/BT/CH/ST/WCT/RB
  rearing expanded to include river polygons + wetland-flow segments.
  Pass `rules = FALSE` to restore pre-0.12.0 behavior.
- Phase 2 MAD support deferred to
  [\#114](https://github.com/NewGraphEnvironment/fresh/issues/114)

## fresh 0.11.1

Gradient barrier label format precision fix.

- New `gradient_NNNN` label format — 4-digit zero-padded basis points
  (threshold × 10000) preserves precision for fractional thresholds.
  `0.05` → `gradient_0500`, `0.0549` → `gradient_0549`, `0.15` →
  `gradient_1500`. Resolution: 1 basis point
  ([\#110](https://github.com/NewGraphEnvironment/fresh/issues/110))
- Fixes silent precision loss in 0.11.0 where `as.integer(thr * 100)`
  collapsed `0.05` and `0.0549` both to `gradient_5`, causing distinct
  biological thresholds to share a single break
- New `.frs_validate_gradient_thresholds()` errors on out-of-range,
  excess precision, NA, or label-collision inputs (catches the bug class
  going forward)
- Parser `.frs_access_label_filter()` accepts BOTH new format and legacy
  `gradient_N` for backward compat with user-supplied labels via
  `frs_break_find(label = "gradient_15")`

## fresh 0.11.0

Sub-segment gradient resolution via auto-derived breaks.

- `breaks_gradient` parameter on
  [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
  — generates gradient breaks at biologically meaningful thresholds
  derived from `spawn_gradient_max` + `rear_gradient_max` in
  `parameters_habitat_thresholds.csv`. Three modes: `NULL` (default
  auto-derive), numeric vector (explicit override), `numeric(0)`
  (disable, 0.10.0 behavior)
  ([\#101](https://github.com/NewGraphEnvironment/fresh/issues/101))
- Default behavior change:
  [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
  now produces ~30% more segments on typical sub-basins (ADMS test: 312
  → 409). The added breaks are at biologically meaningful gradient
  thresholds and give
  [`frs_cluster()`](https://newgraphenvironment.github.io/fresh/reference/frs_cluster.md)
  the resolution it needs to detect within-segment steep sections that
  would otherwise be hidden by averaging
- Pass `breaks_gradient = numeric(0)` to restore 0.10.0 behavior (only
  species access thresholds)

## fresh 0.10.0

Network cluster connectivity analysis.

- [`frs_cluster()`](https://newgraphenvironment.github.io/fresh/reference/frs_cluster.md)
  — generic cluster connectivity validation. Groups adjacent segments
  sharing one label, checks if another label exists upstream,
  downstream, or both on the network. Disconnected clusters set to
  FALSE. Uses `ST_ClusterDBSCAN` for spatial clustering and
  `fwa_downstreamtrace()` for downstream trace with gradient bridge and
  distance cap
  ([\#107](https://github.com/NewGraphEnvironment/fresh/issues/107))
- Per-species cluster config in `parameters_fresh.csv` —
  `cluster_rearing`, `cluster_direction`, `cluster_bridge_gradient`,
  `cluster_bridge_distance`, `cluster_confluence_m`. Anadromous species
  opt in; resident species do not
- `direction = "both"` evaluates upstream and downstream independently,
  keeps clusters valid in either direction

## fresh 0.9.0

Flexible AOI, configurable access gating, and feature indexing.

- [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
  accepts any AOI — sf polygons, WHERE clauses, ltree filters — not just
  WSG codes. Add `species` and `label` params for custom runs
  ([\#96](https://github.com/NewGraphEnvironment/fresh/issues/96))
- `gate` parameter on
  [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  — set `FALSE` to classify raw habitat potential without access
  restrictions
  ([\#98](https://github.com/NewGraphEnvironment/fresh/issues/98))
- `blocking_labels` parameter — configurable which labels restrict
  access. Default `"blocked"`. Set `c("blocked", "potential")` for
  conservative analysis. Only `"blocked"` and `gradient_N` block by
  default; everything else passes through
- [`frs_feature_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_find.md)
  — locate any point features on the network (crossings, observations,
  stations) with `col_id` for feature identity
  ([\#92](https://github.com/NewGraphEnvironment/fresh/issues/92))
- [`frs_feature_index()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_index.md)
  — index upstream/downstream relationships between segments and
  features as ID arrays
  ([\#93](https://github.com/NewGraphEnvironment/fresh/issues/93))
- [`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md)
  slimmed to gradient-only. Point/table modes moved to
  [`frs_feature_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_find.md)
- Province-wide run completed: 229 WSGs, 5.98M segments
- Classify growth penalty fixed: constant-time DELETE by
  `watershed_group_code`
  ([\#91](https://github.com/NewGraphEnvironment/fresh/issues/91))

## fresh 0.8.0

Unified pipeline, domain-agnostic network segmentation, and major
performance improvements.

### New functions

- [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)
  — domain-agnostic network segmentation. Extracts, enriches, breaks at
  any point sources, assigns `id_segment`. One table, one copy of
  geometry.
- [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  — long-format habitat classification. One row per segment x species
  with `accessible`, `spawning`, `rearing`, `lake_rearing`.
  Species-specific accessibility via break label filtering.
- [`frs_feature_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_find.md)
  — locate any point features on the network (crossings, observations,
  stations). Replaces
  [`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md)
  points/table modes.
- [`frs_feature_index()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_index.md)
  — index upstream/downstream relationships between segments and
  features. Stores feature ID arrays per segment.

### Pipeline changes

- [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
  rewritten to wrap
  [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md) +
  [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md).
  Auto-generates gradient barriers per WSG from species parameters.
- `to_streams` + `to_habitat` params replace `to_prefix` for persistent
  output tables.
- mirai replaces furrr for parallel execution — lighter daemons,
  foundation for crew.aws.batch.
- [`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md)
  slimmed to gradient-only (island detection). Point/table modes moved
  to
  [`frs_feature_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_find.md).

### Performance

- Island-based gradient barriers: 85% fewer barriers than interval
  method
  ([\#86](https://github.com/NewGraphEnvironment/fresh/issues/86))
- Accessibility recycled by threshold group: 5 queries → 2 for species
  sharing thresholds
  ([\#89](https://github.com/NewGraphEnvironment/fresh/issues/89))
- Classify growth penalty fixed: constant time DELETE by
  `watershed_group_code`
  ([\#91](https://github.com/NewGraphEnvironment/fresh/issues/91))
- Breaks table indexed with ltree GIST for cross-BLK queries: 15x
  speedup
- Province-wide: 229 WSGs, 5.98M segments completed

### Other

- `id_segment` for unique sub-segment identity after breaking
  ([\#82](https://github.com/NewGraphEnvironment/fresh/issues/82))
- `col_blk` + `col_measure` on break sources for configurable column
  names ([\#80](https://github.com/NewGraphEnvironment/fresh/issues/80))
- `.frs_sql_num()` for locale-safe numeric SQL literals
- Docker-based local fwapg tuned for M4 Max Pro (128GB/16 cores)

## fresh 0.7.0

Local Docker fwapg instance and generic network-referenced
classification via `break_sources`.

- Replace `falls` parameter with `break_sources` list across pipeline
  ([`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md),
  [`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
  [`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md))
  — accepts any number of point tables with `label`, `label_col`, and
  `label_map` for flexible classification
  ([\#70](https://github.com/NewGraphEnvironment/fresh/issues/70))
- Add `label` and `source` columns to breaks table for provenance
  tracking
- Ship `inst/extdata/falls.csv` (3,294 barrier falls) and
  `inst/extdata/crossings.csv` (533k crossings) with `data-raw/` refresh
  scripts
- Add Docker-based local fwapg: containerized PostGIS + loader with
  GDAL/psql/bcdata
  ([\#63](https://github.com/NewGraphEnvironment/fresh/issues/63))
- Fix Phase 2 sequential mode to reuse `conn` instead of calling
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)

## fresh 0.6.0

Parallelized multi-WSG habitat pipeline — 2.5x speedup over sequential
on BULK.

- Add
  [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
  — orchestrator: run the full habitat pipeline across watershed groups
  with `furrr` parallelism
  ([\#61](https://github.com/NewGraphEnvironment/fresh/issues/61))
- Add
  [`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md)
  — generic partition prep (extract, enrich, pre-compute breaks).
  Accepts any AOI, not just WSG codes
- Add
  [`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md)
  — gradient + falls barrier computation at a threshold, deduplicated
  across species sharing the same `access_gradient_max`
- Add
  [`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md)
  — classify one species with pre-computed access and habitat breaks
- Both Phase 1 (partition prep across WSGs) and Phase 2 (species
  classification) parallelize via
  [`furrr::future_map()`](https://furrr.futureverse.org/reference/future_map.html)
  when `workers > 1`
- Benchmark scripts and logs in `scripts/habitat/`

## fresh 0.5.0

Watershed-group habitat pipeline — run the full pipeline across all
species in a WSG.

- Add `where` parameter to
  [`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)
  for SQL predicate filtering, ANDed with `aoi` when both provided
  ([\#60](https://github.com/NewGraphEnvironment/fresh/issues/60))
- Add
  [`frs_wsg_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_wsg_species.md)
  to look up species presence and bcfishpass view names per watershed
  group from bundled `wsg_species_presence.csv`
- Add `data-raw/pipeline_wsg.R` — runs full habitat pipeline per species
  per WSG with timing (baseline: 20 min for BULK, 7 species, 32K
  segments)

## fresh 0.4.1

- Add
  [`frs_categorize()`](https://newgraphenvironment.github.io/fresh/reference/frs_categorize.md)
  for priority-ordered boolean-to-category collapse — mapping codes for
  QGIS, reporting, gq style registry
  ([\#57](https://github.com/NewGraphEnvironment/fresh/issues/57))
- Refine habitat pipeline vignette: code below each narrative section
  with function links, 2x2 scenario grid, access barriers on habitat map

## fresh 0.4.0

Coho habitat pipeline — classify habitat on the database at any scale.
New vignette proves the workflow on the Byman-Ailport subbasin of the
Neexdzii Kwa.

- Add
  [`frs_col_join()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_join.md)
  for generic lookup table enrichment — channel width, MAD, upstream
  area, any key
  ([\#51](https://github.com/NewGraphEnvironment/fresh/issues/51))
- Add
  [`frs_edge_types()`](https://newgraphenvironment.github.io/fresh/reference/frs_edge_types.md)
  lookup helper with bundled FWA edge type CSV (41 codes from GeoBC User
  Guide)
- Add `to` param to
  [`frs_network()`](https://newgraphenvironment.github.io/fresh/reference/frs_network.md)
  — write results to DB working tables instead of pulling to R, scales
  to any number of watershed groups
  ([\#53](https://github.com/NewGraphEnvironment/fresh/issues/53))
- Add `where` param to
  [`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md)
  — scope classification by SQL predicate for edge-type-aware and
  accessibility-filtered habitat modelling
- Add `where` and `append` params to
  [`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md)
  table mode — filter points table and combine multiple break sources
  (gradient + falls) in one breaks table
  ([\#38](https://github.com/NewGraphEnvironment/fresh/issues/38))
- Add `exclude_edge_types` param to
  [`frs_point_snap()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_snap.md)
  — only exclude subsurface flow (1425) by default, not wetland
  connectors (1410)
  ([\#52](https://github.com/NewGraphEnvironment/fresh/issues/52))
- Bundle bcfishpass habitat parameter CSVs and fresh-specific access
  gradient thresholds
  ([\#54](https://github.com/NewGraphEnvironment/fresh/issues/54))
- Add coho habitat pipeline vignette: extract → enrich → break
  (gradient + falls) → classify (accessible, spawning, rearing, lake
  rearing) → aggregate → scenario comparison

## fresh 0.3.1

- Add `from` and `extra_where` params to waterbody specs in
  [`frs_network()`](https://newgraphenvironment.github.io/fresh/reference/frs_network.md)
  for filtering waterbodies to those connected to habitat streams
  ([\#49](https://github.com/NewGraphEnvironment/fresh/issues/49))
- Network traversal table configurable via `.frs_opt("tbl_network")`
  ([\#44](https://github.com/NewGraphEnvironment/fresh/issues/44))

## fresh 0.3.0

Server-side habitat model pipeline — replaces ~34 bcfishpass SQL scripts
with 4 composable functions. See the [function
reference](https://newgraphenvironment.github.io/fresh/reference/) for
details.

- Add
  [`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)
  for staging read-only data to writable working schema
  ([\#36](https://github.com/NewGraphEnvironment/fresh/issues/36))
- Add
  [`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md)
  family (`find`, `validate`, `apply`, wrapper) for network geometry
  splitting via `ST_LocateBetween` and `fwa_slopealonginterval` gradient
  sampling
  ([\#38](https://github.com/NewGraphEnvironment/fresh/issues/38))
- Add
  [`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md)
  for labeling features by attribute ranges, break accessibility (via
  `fwa_upstream`), and manual overrides — pipeable for multi-label
  classification
  ([\#39](https://github.com/NewGraphEnvironment/fresh/issues/39))
- Add
  [`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md)
  for network-directed feature summarization from points
  ([\#40](https://github.com/NewGraphEnvironment/fresh/issues/40))
- Add
  [`frs_col_generate()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_generate.md)
  to convert gradient/measures/length to PostgreSQL generated columns —
  auto-recompute after geometry changes
  ([\#45](https://github.com/NewGraphEnvironment/fresh/issues/45))
- Add `.frs_opt()` for configurable column names via
  [`options()`](https://rdrr.io/r/base/options.html) — foundation for
  spyda compatibility
  ([\#44](https://github.com/NewGraphEnvironment/fresh/issues/44))
- All write functions return `conn` invisibly for consistent `|>`
  chaining

## fresh 0.2.0

CRAN release: 2020-05-29

- **Breaking:** All DB-using functions now take `conn` as the first
  required parameter instead of `...` connection args. Create a
  connection once with `conn <- frs_db_conn()` and pass it to all calls.
  Enables piping: `conn |> frs_break() |> frs_classify()`
  ([\#35](https://github.com/NewGraphEnvironment/fresh/issues/35))

## fresh 0.1.0

CRAN release: 2019-10-21

- Multi-blue-line-key support for
  [`frs_watershed_at_measure()`](https://newgraphenvironment.github.io/fresh/reference/frs_watershed_at_measure.md)
  and
  [`frs_network()`](https://newgraphenvironment.github.io/fresh/reference/frs_network.md)
  via `upstream_blk` param
  ([\#20](https://github.com/NewGraphEnvironment/fresh/issues/20))
- Add
  [`frs_watershed_at_measure()`](https://newgraphenvironment.github.io/fresh/reference/frs_watershed_at_measure.md)
  for watershed polygon delineation with subbasin subtraction
- Add
  [`frs_network()`](https://newgraphenvironment.github.io/fresh/reference/frs_network.md)
  unified multi-table traversal function replacing per-type fetch
  functions
- Add `frs_default_cols()` with sensible column defaults for streams,
  lakes, crossings, fish obs, and falls
- Add `upstream_measure` param for network subtraction between two
  points on the same stream
- Add
  [`frs_waterbody_network()`](https://newgraphenvironment.github.io/fresh/reference/frs_waterbody_network.md)
  for upstream/downstream lake and wetland queries via waterbody key
  bridge
- Add `wscode_col`, `localcode_col`, and `extra_where` params for custom
  table schemas
- Add `frs_check_upstream()` validation for cross-BLK network
  connectivity
- Add `blue_line_key` and `stream_order_min` params to
  [`frs_point_snap()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_snap.md)
  for targeted snapping via KNN
  ([\#16](https://github.com/NewGraphEnvironment/fresh/issues/16),
  [\#17](https://github.com/NewGraphEnvironment/fresh/issues/17),
  [\#7](https://github.com/NewGraphEnvironment/fresh/issues/7),
  [\#18](https://github.com/NewGraphEnvironment/fresh/issues/18))
- Add stream filtering guards: exclude placeholder streams (999 wscode)
  and unmapped tributaries (NULL localcode) from network queries;
  `include_all` to bypass. Subsurface flow (edge_type 1410/1425) kept in
  network results (real connectivity) but excluded from KNN snap
  candidates
  ([\#15](https://github.com/NewGraphEnvironment/fresh/issues/15))
- Add
  [`frs_clip()`](https://newgraphenvironment.github.io/fresh/reference/frs_clip.md)
  for clipping sf results to an AOI polygon, with `clip` param on
  [`frs_network()`](https://newgraphenvironment.github.io/fresh/reference/frs_network.md)
  for inline use
  ([\#12](https://github.com/NewGraphEnvironment/fresh/issues/12))
- Add
  [`frs_watershed_split()`](https://newgraphenvironment.github.io/fresh/reference/frs_watershed_split.md)
  for programmatic sub-basin delineation from break points — snap,
  delineate, subtract with stable `blk`/`drm` identifiers
  ([\#31](https://github.com/NewGraphEnvironment/fresh/issues/31))
- Security hardening: quote string values in SQL, validate table/column
  identifiers, clear error on missing PG env vars, gitignore credential
  files ([\#19](https://github.com/NewGraphEnvironment/fresh/issues/19))
- Input type validation on all numeric params
- Add subbasin query vignette with tmap v4 composition
- Fix ref CTE to always query stream network, not target table

Initial release. Stream network-aware spatial operations via direct SQL
against fwapg and bcfishpass. See the [function
reference](https://newgraphenvironment.github.io/fresh/reference/) for
details.
