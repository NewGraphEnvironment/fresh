# Changelog

## fresh 0.31.0

Closes [\#207](https://github.com/NewGraphEnvironment/fresh/issues/207).
Adds
[`frs_candidates_pick()`](https://newgraphenvironment.github.io/fresh/reference/frs_candidates_pick.md)
— fourth primitive in the point-handling family (alongside
`frs_point_snap`, `frs_network_features`, `frs_point_match`). Given a
candidates table where multiple rows can share the same key value,
optionally compute a per-row score from a caller-supplied SQL
expression, optionally filter via a caller-supplied WHERE clause, then
keep one row per key via `DISTINCT ON (col_key) ORDER BY ...`.

- Generic over any “score + filter + dedup per key” workflow where
  column-to-column comparisons disambiguate matches: stream-name
  matching, watershed-group agreement, species-code overlap,
  assessment-date proximity, channel-width × stream-order compatibility,
  etc.
- Closes the BULK 5-diff gap from fresh#206 at the dedup-step level.
  Live validation on BULK PSCIS-to-stream selection (using bcfp’s
  pre-computed `pscis_streams_150m` as the scored-candidates input):
  **102 / 102 ref picks byte-identical**, 0 missing. The 4 “extras” are
  bcfp’s downstream `suspect_match` routing filter that lives
  caller-side, not in this primitive.
- Parameter naming follows the `table_<role>` / `col_<role>` /
  `exp_<role>` conventions (link/CLAUDE.md): `table_in`, `table_to`,
  `col_key`, `exp_score`, `exp_filter`, `order_by`.
- Composition: `frs_point_snap(num_features = N)` →
  `frs_candidates_pick(exp_score, exp_filter, order_by)` →
  `frs_point_match(distance_max, tiebreak)` reproduces the bcfp
  PSCIS-build pipeline byte-identically. First consumer: link#154
  (`lnk_pipeline_crossings` PSCIS↔︎modelled auto-snap), which will rewire
  to this three-step composition.
- SQL composition: optional
  `WITH scored AS (SELECT *, (<exp_score>) AS score FROM <table_in>)`
  CTE; `SELECT DISTINCT ON (<col_key>) * FROM (scored | table_in)`;
  optional `WHERE <exp_filter>`;
  `ORDER BY <col_key>, <caller's order_by clauses>`. `col_key` prepended
  to ORDER BY to satisfy PostgreSQL’s DISTINCT-ON requirement. DROP +
  CREATE split into two
  [`DBI::dbExecute`](https://dbi.r-dbi.org/reference/dbExecute.html)
  calls (RPostgres can’t run multi-statement SQL).
- 25 mocked tests covering input validation, identifier sanitization,
  reserved-column collision (when `exp_score` set), SQL composition
  (full path + `exp_score = NULL` variant + `exp_filter = NULL`
  variant), and the existing-`score`-column-allowed-when-exp_score-null
  edge case.

## fresh 0.30.0

Closes [\#206](https://github.com/NewGraphEnvironment/fresh/issues/206).
Adds
[`frs_point_match()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_match.md)
— a third primitive in the point-handling family alongside
`frs_point_snap` (point↔︎stream) and `frs_network_features`
(segment↔︎feature dnstr/upstr). Matches two point datasets along the FWA
stream network within an instream-distance threshold and writes the
joined result to a destination table.

- Generic over any pair of FWA-snapped point datasets (PSCIS↔︎modelled
  crossings, observations↔︎habitat confirmations,
  field-assessed↔︎user-added crossing dedup, etc.). All point inputs must
  already carry `blue_line_key` and `downstream_route_measure` (the FWA
  convention) — typically via `frs_point_snap` upstream.
- Algorithm mirrors bcfp’s `02_pscis_streams_150m.sql` (at
  `smnorris/bcfishpass@v0.7.14-125-g6e9cf1c`, tunnel
  `bcfishpass.log.model_run_id=121` rebuilt 2026-05-05) —
  same-`blue_line_key` join + `ABS(drm_a - drm_b) < distance_max` +
  `DISTINCT ON (table_a_id, blue_line_key) ORDER BY distance_instream ASC NULLS LAST`.
  LEFT JOIN preserves `table_a` rows with no match (their
  `table_b_id_col` ends up NULL).
- Function parameters follow the `table_*` convention from
  link/CLAUDE.md: `table_a` / `table_b` / `table_to` for the three
  tables, `table_a_id_col` / `table_b_id_col` for the ID columns.
- Network-position columns (`blue_line_key`, `downstream_route_measure`)
  hard-coded to the FWA convention. Per-side overrides (à la
  `frs_network_features` v0.29.0) can be added if a real divergence
  appears.
- Write-to-table contract: drops + recreates `table_to` via two separate
  [`DBI::dbExecute`](https://dbi.r-dbi.org/reference/dbExecute.html)
  calls (RPostgres requires one statement per call). Returns `conn`
  invisibly. Different from `frs_point_snap` (returns sf) and
  `frs_network_features` (returns tibble) because the result here is a
  derived *dataset* not a query result, and bcfp’s analog also writes
  table→table.
- Live parity on ADMS PSCIS↔︎modelled at 100m instream: **60 / 60
  (stream_crossing_id, modelled_crossing_id) pairs byte-identical** to
  `bcfishpass.pscis.modelled_crossing_id`. 0 in ours-not-ref, 0 in
  ref-not-ours.
- Live parity on BULK PSCIS↔︎modelled (xref-excluded snap-only subset):
  **77 / 78 ref pairs identical** (98.7% on ref, 5 in ours-not-ref). The
  4–5 BULK edge-case divergences are documented in the function’s
  `@details` — bcfp considers multi-stream candidates within 150m planar
  before settling on (PSCIS, stream), while `frs_point_match` assumes
  the caller has already snapped each PSCIS to one stream. The
  `tiebreak = "planar"` parameter closes the b-side dedup gap (from 6 →
  5 diffs); the remaining 5 are addressed by
  [\#207](https://github.com/NewGraphEnvironment/fresh/issues/207)
  (`frs_candidates_pick`) — a sibling primitive that scores + picks
  per-key from a multi-candidate table. With
  [\#206](https://github.com/NewGraphEnvironment/fresh/issues/206) +
  [\#207](https://github.com/NewGraphEnvironment/fresh/issues/207)
  composed, the bcfp PSCIS-to-stream + PSCIS-to-modelled algorithm
  reproduces byte-identically.
- `tiebreak` parameter (`c("instream", "planar")`) controls the b-side
  dedup metric. Default `"instream"` (`ABS(drm_a - drm_b)`) requires no
  geometry and is self-consistent with the threshold filter. `"planar"`
  (`ST_Distance(a.geom, b.geom)`) mirrors bcfp’s
  `02_pscis_streams_150m.sql` line 190 tiebreak; requires `geom` column
  on both tables.
- 21 mocked tests covering validation (required args, scalar positive
  numeric `distance_max`, identifier sanitization, same-name guard) and
  SQL composition (DROP + CREATE order, DISTINCT ON,
  same-`blue_line_key` join predicate, `distance_max` literal, LEFT
  JOIN, ASC NULLS LAST tiebreak, ID-column carry-through).
- First consumer: link#154
  (`lnk_pipeline_crossings: missing PSCIS↔︎modelled 100m-instream auto-snap layer`)
  which wires this primitive into link’s per-WSG crossings build.

## fresh 0.29.0

Closes [\#204](https://github.com/NewGraphEnvironment/fresh/issues/204).
Two ergonomic upgrades to
[`frs_network_features()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_features.md)
surfaced when wiring it into link’s `lnk_pipeline_access` (link#124).

- Per-side wscode/localcode column overrides. New args
  `segments_wscode_col`, `segments_localcode_col`,
  `features_wscode_col`, `features_localcode_col` (all default
  `"wscode_ltree"` / `"localcode_ltree"`). The original “unified” intent
  in [\#204](https://github.com/NewGraphEnvironment/fresh/issues/204)
  didn’t survive contact with `bcfishpass.observations` (unsuffixed
  `wscode` / `localcode`) joined against `bcfishpass.streams` (`_ltree`)
  — segments and features can have different column conventions on the
  same query. Pass `features_wscode_col = "wscode"` +
  `features_localcode_col = "localcode"` for that case.
- `feature_ids` is now an R list-column of character vectors rather than
  a `pq__text` column of array-literal strings (`"{a,b,c}"`). Callers
  can [`lengths()`](https://rdrr.io/r/base/lengths.html),
  [`lapply()`](https://rdrr.io/r/base/lapply.html), `%in%` directly.
  Empty / NULL arrays parse to `character(0)`. Internal helper
  `.frs_parse_pg_array()` does the parse — limited to unquoted-element
  arrays (the common case for FWA-snapped IDs); arrays containing commas
  or quotes inside elements would need a fuller parser per [PostgreSQL
  arrays
  I/O](https://www.postgresql.org/docs/current/arrays.html#ARRAYS-IO).
- Live parity on ADMS PSCIS barriers: still 1031 / 1031 byte-identical
  to bcfp.
- Live test added covers `bcfishpass.observations` with the per-side
  override — confirms column-resolution succeeds and `feature_ids[[1]]`
  is a character vector of `observation_key` strings, not a `{...}`
  literal.

## fresh 0.28.0

Closes [\#201](https://github.com/NewGraphEnvironment/fresh/issues/201).
Adds
[`frs_network_features()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_features.md)
— a direction-agnostic primitive that returns per-segment arrays of
features at a relative position on the FWA stream network. For each row
in a segments table, the function `array_agg`s feature IDs from a
features table that lie either downstream of, or upstream of, that
segment. Generic over any FWA-snapped point dataset (barriers,
observations, water-quality stations, fish surveys, sediment samples —
anything keyed by
`(blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree)`).

- Sibling to `frs_network_downstream` / `frs_network_upstream` (which
  are point→segments). New shape: segments→features (per-segment
  arrays).
- `direction = c("downstream", "upstream")` is required (no default).
  [`match.arg()`](https://rdrr.io/r/base/match.arg.html) enforces.
- `aoi` defaults to `NULL` (process all segments). Accepts WSG codes
  today; polygon / ltree forward-compat — will route through
  `.frs_resolve_aoi()` when generalised.
- Output is a 2-column tibble. `feature_ids` is `text[]`; segments with
  zero matches are absent from the output (INNER-JOIN semantics,
  mirroring `bcfishpass.load_dnstr`). Callers wanting
  all-segments-with-NULL can LEFT-JOIN the result back to their segments
  table.
- SQL pattern mirrors `bcfishpass.load_dnstr` exactly:
  subquery-INNER-JOIN feeding outer GROUP BY, with the canonical
  `ORDER BY segment_id, wscode DESC, localcode DESC, drm DESC` triple at
  the subquery level for byte-identical element ordering.
- Live parity test against bcfp’s `streams_dnstr_barriers` for ADMS
  PSCIS barriers: 1031 / 1031 segments byte-identical (mod sort).
- First consumer: link’s `lnk_pipeline_access` (link#124, in flight) —
  composes calls across (source × species) into the bcfp-shape
  `streams_access` table.

## fresh 0.27.6

Set SSD-friendly planner-cost defaults in `docker/docker-compose.yml`:
`random_page_cost=1.1`, `effective_io_concurrency=200`,
`temp_buffers=64MB`. PostgreSQL ships with values calibrated for
spinning rust (4.0 / 1 / 8MB), which biased the planner away from index
scans on segment-keyed lookups (`WHERE blue_line_key = … AND drm <= …`
against `streams_breaks` is the hot path in link’s pipeline). Documents
the new settings in `docker/tuning.md` and notes that the M1/cypher
docker-compose override file (tracked separately) needs the same flags —
compose merges override `command:` lists by replacing the base, not
appending.

## fresh 0.27.5

`channel_width_min_bypass` block schema change: replace single
`stream_order` key with `stream_order_min` + `stream_order_max` to
express child-order ranges. The single key was modeling only
`stream_order = 1` (bcfp parity), but `frs_order_child` always supported
a range — `child_order_min` / `child_order_max` parameters. The new pair
maps directly. Validator rejects the legacy `stream_order` key with
`unknown keys` to flag stale rules.yaml files for regeneration.

Unblocks link’s `dimensions.csv::rear_stream_order_child_min` /
`rear_stream_order_child_max` columns. No behaviour change for
`frs_order_child` itself; this is a YAML schema rename only.

## fresh 0.27.4

Allow optional `distance_max` key inside `channel_width_min_bypass`
block in rules YAML — link uses it to cap the bypass to the lower N
metres of each direct-trib BLK
(i.e. `frs_order_child(distance_max = N)`). Validator accepts a positive
numeric scalar; rejects zero / negative / non-numeric values.

## fresh 0.27.3

Restore `stream_order_max` predicate in
[`frs_order_child()`](https://newgraphenvironment.github.io/fresh/reference/frs_order_child.md)
— the previous patch (0.27.2) removed the
`s.stream_order = s.stream_order_max` filter because the column doesn’t
exist on `fresh.streams`. That was the wrong fix: the predicate is
load-bearing for direct-child semantics. Without it, multi-order BLKs
like a named creek that grows from order-1 headwaters to order-3 mouth
(e.g. Divan Creek, BLK 356353593 in HORS) get their order-1 headwater
segments credited as direct trib mouths of large rivers — they are not.

Fix: derive `stream_order_max` per BLK on the fly via
`MAX(stream_order) OVER (PARTITION BY blue_line_key)` in a CTE, then
apply `s.stream_order = s.stream_order_max` to bound the bypass to
mouth-side reaches only. Same answer as
`bcfishpass.streams.stream_order_max` (which is a stored column there).
Verified against HORS BT — eliminates ~95 km of spurious credit on
multi-order BLK headwaters.

## fresh 0.27.2

Fix
[`frs_order_child()`](https://newgraphenvironment.github.io/fresh/reference/frs_order_child.md)
SQL referencing nonexistent column `s.stream_order_max`. `fresh.streams`
has `stream_order` and `stream_order_parent` from FWA but no
`stream_order_max` — the 0.27.0 SQL failed at execution against any real
database (only the SQL-shape unit tests passed, and they asserted the
broken predicate). Drop the broken predicate; default both
`child_order_min` and `child_order_max` to `1L` when neither is set,
which matches bcfishpass’s hardcoded `stream_order = 1` predicate
exactly. Caller-passed bounds still apply unchanged.

Adds a regression test that scans the emitted SQL across every parameter
combination for `stream_order_max` and fails if it reappears.

## fresh 0.27.1

Patch follow-up to 0.27.0. `.frs_load_rules` validator now accepts the
`channel_width_min_bypass` predicate that link emits to drive
[`frs_order_child()`](https://newgraphenvironment.github.io/fresh/reference/frs_order_child.md)
post-classify (link#96 wiring). Validates that the field is a named
mapping with `stream_order` and `stream_order_parent_min` integer
scalars. Without this patch, link’s emitted rules.yaml fails fast at
[`frs_params()`](https://newgraphenvironment.github.io/fresh/reference/frs_params.md)
with `unknown predicates: channel_width_min_bypass` before any
classification runs.

## fresh 0.27.0

Closes [\#158](https://github.com/NewGraphEnvironment/fresh/pull/193).
New
[`frs_order_child()`](https://newgraphenvironment.github.io/fresh/reference/frs_order_child.md):
post-classification UPDATE that credits direct order-1 (or other)
tributaries of order-N+ rivers with `<label> = TRUE`. Captures the
bcfishpass rearing bypass currently hard-coded in
`model/02_habitat_linear/sql/load_habitat_linear_<sp>.sql` for
BT/CH/CO/ST/WCT — predicate
`cw.channel_width >= rear_channel_width_min OR (s.stream_order_parent >= 5 AND s.stream_order = 1)`.

- Parametric: `parent_order_min` (default `5L` matches bcfp),
  `child_order_min/max`, `distance_max`. Generic on label column
  (`rearing` / `lake_rearing` / `wetland_rearing`).
- Idempotent + additive: `<label> IS NOT TRUE` guard. Never adds rearing
  above an inaccessible barrier: `accessible = TRUE` guard.
- No existing-caller behaviour change. Wiring into link’s pipeline is a
  follow-up PR (link side: `lnk_pipeline_classify` calls
  `frs_order_child` post-classify per-species, gated on
  `dimensions.csv::rear_stream_order_bypass`).

## fresh 0.26.0

Closes [\#191](https://github.com/NewGraphEnvironment/fresh/pull/192).
`.frs_connected_waterbody` Phase 2 (upstream spawn) cluster +
lake-adjacency gate is now opt-out via a `lake_adjacent` parameter on
the rule. Default `TRUE` keeps bcfishpass-parity behaviour
byte-identical for any caller not setting the knob; passing
`lake_adjacent: no` in `<sp>.spawn_connected.lake_adjacent` runs the
relaxed Phase 2 that credits any spawn-eligible segment upstream of and
accessible from a qualifying rearing waterbody. Used by callers that
need to credit upstream tributary reaches not in lake-adjacent clusters
(e.g. NewGraph default-bundle SK methodology — link#87).
`.frs_load_rules` validator updated to accept the new key.

Cross-host testing pattern (m4 ↔︎ m1 over Tailscale, with
[`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html) overrides for
`PG_*_SHARE` to point fresh tests at a host’s local Docker fwapg when
the bcfp tunnel is unavailable) documented in `CLAUDE.md` “Testing on
alternate hosts.”

## fresh 0.25.0

Two bcfishpass-parity fixes surfaced during link’s WSG-coverage
expansion (link’s MORR + KISP runs, 2026-04-30).

**`frs_cluster` phase-1 + confluence-boost interaction**
([\#186](https://github.com/NewGraphEnvironment/fresh/issues/186)).
`.frs_cluster_both` previously excluded on-spawning rearing segments
from the clustering CTE. Removing those segments could shift
`cluster_minimums` into the confluence-boost zone (DRM \<
`confluence_m`) and validate clusters that `bridge_gradient` should
deny. bcfishpass’s path-2 keeps on-spawning segments in clusters, so its
cluster_min stays high and the confluence boost doesn’t fire. Phase-1
protection now lives only in the final `UPDATE` step — on-spawning
segments retain `label_cluster = TRUE` regardless of cluster outcome,
but the cluster boundaries used for phase-2 / phase-3 testing are
unchanged. Reproduction case: MORR ST cluster 502 (Nado Creek +
tributary 360704379, 12.58% gradient between trib confluence and
downstream spawning) — bcfp denies the trib’s rearing-eligible segments;
fresh now matches.

**`.frs_trace_downstream` averaged FWA gradient**
([\#187](https://github.com/NewGraphEnvironment/fresh/issues/187)).
`.frs_trace_downstream` previously used
`whse_basemapping.fwa_downstreamtrace`, an iterator returning
FWA-original `linear_feature_id` rows with feature-averaged gradients.
Localized barriers on a sub-piece of a long FWA feature (e.g. a 7 m, 84%
lake-outlet drop inside an otherwise flat 3 km feature) are invisible to
that approach. Switched to a `FWA_Downstream` predicate join against the
broken streams `table` arg — same pattern `.frs_cluster_both` phase-3
already uses. Localized gradients produced by
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)
are now visible to the trace. New required columns in `origins_sql`:
`wscode_ltree`, `localcode_ltree` (`.frs_connected_waterbody` is the
only caller; updated). Reproduction case: KISP SK at Kitwancool Lake —
bcfp’s `model/02_habitat_linear/sql/load_habitat_linear_sk.sql`
correctly stops at the lake-outlet drop; fresh now matches.

Both fixes tighten link’s bcfishpass-config parity rollup. No API
changes for end users; `.frs_trace_downstream` is an internal helper.
NEWS bump from 0.24.1 → 0.25.0 because behaviour changes are observable
in `frs_habitat_classify` / `frs_cluster` / `frs_habitat` outputs for
any caller running connectivity or cluster-aware classifications.

## fresh 0.24.1

Refresh bundled `inst/extdata/parameters_habitat_rules.yaml` to match
link’s current default-bundle output. The bundled sample had drifted to
pre-`in_waterbody` / pre-`area_only` shape (last synced 2026-04-12)
while link’s bundles evolved through three
[\#69](https://github.com/NewGraphEnvironment/fresh/issues/69) phases.
Sync recovers the canonical sample for any
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
caller using fresh’s bundled defaults.

Reframe `vignettes/habitat-pipeline.Rmd` as a primitives walkthrough.
Header note up front directs production users to
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
and link’s rule-based pipeline; vignette body unchanged — primitives are
still useful for debugging, custom pipelines, and understanding what
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
does internally.

No behaviour change to any exported function.

## fresh 0.24.0

Add `area_only: true` flag to rule grammar — decouples bucket-flag
derivation from the main `rear` predicate
([\#182](https://github.com/NewGraphEnvironment/fresh/issues/182)).

Today, a `waterbody_type: L` or `W` rule placed in a species’ `rear:`
list does two things at once: triggers fresh to derive a `lake_rearing`
/ `wetland_rearing` predicate (the per-segment flag that drives
`lake_rearing_ha` / `wetland_rearing_ha` area rollups), AND OR’s into
the main `rear` predicate (the per-segment `rearing` flag, which drives
linear `rearing_km`). The two effects are coupled, so a user can’t say
“credit the polygon area but exclude polygon-mainlines from linear km.”

This release adds `area_only: true` on a rule. When set, fresh uses the
rule’s predicate to derive the corresponding bucket flag (lake_rearing
or wetland_rearing) but **does not include** the rule in the OR-chain
that builds the main `rear` predicate. Stream-edge rules (with
`in_waterbody: false` from
[\#180](https://github.com/NewGraphEnvironment/fresh/issues/180)) decide
what counts as linear; L/W rules with `area_only: true` decide what
polygons contribute area without double-counting the polygon-mainline as
linear.

- **`area_only: true`** on a `waterbody_type: L|W` rule → rule
  contributes to `lake_rear` / `wetland_rear` predicate derivation only,
  excluded from main `rear` predicate.
- **`area_only: false`** or absent → today’s behaviour (rule contributes
  to both). Backward compatible.
- Validator: requires `waterbody_type: L` or `W` (no bucket flag to
  drive on stream-edge rules or `waterbody_type: R`); rejects
  non-logical / NA / length\>1 values.
- 13 new tests across `test-frs_params.R` (validator) and
  `test-frs_habitat_predicates.R` (decoupling). 167 PASS in those files
  (was 154). Full suite green.

Coordinates with [link#69 phase
2](https://github.com/NewGraphEnvironment/link/issues/69) —
`lnk_rules_build()` will emit `area_only: true` on L/W polygon rule
blocks driven by per-species `rear_lake_area_only` /
`rear_wetland_area_only` columns in `dimensions.csv`. Combined with the
polygon-rule `edge_types_explicit: [1000, 1100]` filter (mainlines
only), this expresses the use-case-2 model: linear excludes
polygon-mainlines, area still rolls up.

## fresh 0.23.1

Hotfix on top of 0.23.0 — register `in_waterbody` with the rules-YAML
validator so emitted rules pass loading.

`.frs_load_rules()` validates each rule entry’s keys against an
allowlist of known predicates (`valid_predicates` in `R/frs_params.R`).
0.23.0 added the predicate at the SQL emission layer
(`.frs_rule_to_sql()`) but missed adding it to the allowlist, so a rules
YAML carrying `in_waterbody:` was rejected by `.frs_load_rules()` before
SQL emission ever ran. This release adds `in_waterbody` to
`valid_predicates`.

- 1 new test: `.frs_load_rules` accepts a YAML with
  `in_waterbody: true|false` on edge-type and waterbody-type rules (113
  PASS in `test-frs_params.R`, was 112).
- No behaviour change beyond unblocking the predicate that 0.23.0
  introduced.

## fresh 0.23.0

Add `in_waterbody` boolean predicate to the rule grammar
([\#180](https://github.com/NewGraphEnvironment/fresh/issues/180)).

The rule grammar in `parameters_habitat_rules.yaml` already had positive
predicates for selecting segments inside polygon waterbodies
(`waterbody_type: R/L/W`) but no symmetric way to restrict a rule to
segments **outside** any waterbody. That left the stream-edge rule
families silent on polygon membership, so a stream rule like
`edge_types_explicit: [1000, 1100, 2000, 2300]` matched both true
streams and the same-coded centerlines that thread through
wetland/lake/river polygons — overlapping with the polygon rules on
those segments and double-classifying.

This release adds `in_waterbody: false | true` as the natural complement
to `waterbody_type:`. Stream-edge rules can now express “this
classification only applies outside polygon footprints,” which is the
semantic complement of the existing polygon rules. Together the two
predicates partition the network into stream-edge classifications and
polygon-classifications with no overlap.

- **`in_waterbody: false`** → adds `s.waterbody_key IS NULL` to the
  rule’s AND chain.
- **`in_waterbody: true`** → adds `s.waterbody_key IS NOT NULL`.
- **absent** → no constraint (pre-`in_waterbody` behaviour, backward
  compatible).
- Composes with `waterbody_type: <letter>` — the positive predicate
  already implies `IS NOT NULL`, so the two together are redundant
  rather than contradictory.
- Validation: non-logical / NA / length\>1 values raise an error at
  `.frs_rule_to_sql()` time.
- 5 new tests under `test-frs_params.R` (112 in that file, was 107).
  Full suite green.

Coordinates with
[link#69](https://github.com/NewGraphEnvironment/link/issues/69) —
`lnk_rules_build()` will emit `in_waterbody: false` on stream-edge rule
blocks once this lands.

## fresh 0.22.0

[`frs_habitat_overlay()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.md)
simplified — drop `format` and `long_value_col` parameters; accept only
the canonical source-table shape
([\#177](https://github.com/NewGraphEnvironment/fresh/issues/177)).

- **Canonical shape**: one row per (segment × species), with join keys
  in `by`, the species code in `species_col` (default `"species_code"`),
  and one indicator column per habitat type. Indicator coercion accepts
  integer 1, text `'true'`/`'t'`/`'1'` (case + whitespace insensitive),
  boolean.
- **Dropped paths** (breaking, pre-1.0): `format = "wide"`
  per-species-suffix layout (`spawning_sk`, `rearing_sk`) and
  `format = "long"` (`habitat_type` rows + `habitat_ind` indicator).
  Neither had current production consumers — the wide-suffix layout was
  scoped for direct reads of `bcfishpass.streams_habitat_known` (never
  integrated); the long format was link’s read of bcfishpass’s
  pre-2026-04-26 CSV (bcfishpass moved to a different shape on
  2026-04-26).
- **New parameter**: `species_col` (default `"species_code"`). Was added
  in PR
  [\#176](https://github.com/NewGraphEnvironment/fresh/issues/176)’s
  first attempt as an additive bolt-on; this release lands it as the
  only path.
- **Non-canonical sources**: transform first via a SQL view, R pivot, or
  upstream adapter (e.g., link’s forthcoming `lnk_ingest_bcfishpass()`),
  then call overlay against the canonical-shape view. Shape-translation
  lives with the consumer; fresh stays a thin SQL adapter.
- **Bridge mode** (`bridge = NULL`) unchanged — orthogonal to source
  shape.
- Tests: dropped wide-suffix and long-format paths; canonical-shape
  integration tests exercise integer + text + boolean indicators,
  additive guard, custom `species_col`, custom `by`, and bridge mode.

Coordinated link release (0.12.0) updates the call site in
`lnk_pipeline_classify`.

## fresh 0.21.0

[`frs_habitat_overlay()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.md)
rename + 3-way bridge join. Pre-1.0 cleanup driven by review of v0.20.0;
no deprecation alias.

- **Param renames** (breaking):
  - `table` → `to` (matches fresh’s “destination” convention)
  - `known` → `from` (matches “source” convention; also detaches from
    the “known habitat” provenance framing — function is the abstract
    overlay mechanism)
- **New `bridge = NULL` parameter** for 3-way joins. When supplied, the
  SQL becomes `to ← bridge ← from` with range containment:
  `bridge.downstream_route_measure >= from.downstream_route_measure AND bridge.upstream_route_measure <= from.upstream_route_measure`.
  Lets `to` tables keyed by `id_segment` (e.g. `fresh.streams_habitat`)
  overlay from sources keyed by `(blue_line_key, drm)` ranges.
- **Range columns auto-stripped from `by` in bridge mode** —
  `downstream_route_measure` / `upstream_route_measure` are handled by
  the range predicates, so they don’t need to be (and shouldn’t be) in
  the equality `by` clause.
- [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)’s
  `known = NULL` shortcut **dropped** (also breaking). Convenience hid
  configurability now that overlay has format + bridge knobs. Caller
  pattern is now explicitly two-step:
  [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  then
  [`frs_habitat_overlay()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.md).
- Reads as a sentence:
  `frs_habitat_overlay(from = X, to = Y, bridge = Z)` — “overlay flags
  from X to Y via this bridge.” Domain-agnostic — bridge isn’t required
  to be `fresh.streams`; any segments table providing `id_segment` +
  range columns works (lake centerlines, wetland shorelines, future
  cottonwood-pinned segmentations).

Surfaced in
[link#55](https://github.com/NewGraphEnvironment/link/issues/55) when
`fresh.streams_habitat` (keyed by `id_segment` only) needed overlay from
`user_habitat_classification` (keyed by `(blue_line_key, drm)` with
range `[drm, urm]`).

Tests: 52 (was 43 in v0.20.0) — added bridge schema validation, SQL
shape verification, range-containment integration test on a 3-segment
fixture.

## fresh 0.20.0

[`frs_habitat_overlay()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.md)
accepts long-format known-habitat tables in addition to the original
wide-format. Backward-compatible: the new `format` arg defaults to
`"wide"`.

- New args: `format = c("wide", "long")` and
  `long_value_col = "habitat_ind"`.
- Long-format expects: join keys (per `by`) + `species_code` +
  `habitat_type` + a boolean / text indicator column. Each row is one
  (segment × species × habitat_type) tuple. Matches link’s
  `user_habitat_classification.csv` shape, which is the bcfishpass
  `user_habitat_classification.csv` source format (before bcfishpass
  pivots it to wide for `streams_habitat_known`).
- Indicator accepts boolean OR text — `'TRUE'` / `'t'` / `'true'` all
  qualify. Non-matching values (e.g. `'FALSE'`, NULL) skip.
- Up-front validation: long-format known table must have all required
  columns (join keys + `species_code` + `habitat_type` + indicator).
  Errors clearly if missing.
- Wide-format path unchanged. 11 new tests covering long-format unit +
  integration; previous wide tests all still pass (42 total on
  `frs_habitat_overlay`).

Surfaced in
[link#55](https://github.com/NewGraphEnvironment/link/issues/55) —
link’s `user_habitat_classification` table is loaded long-format by
`lnk_pipeline_prepare`. Forcing a pivot in link to satisfy the
wide-format assumption was special-case overhead. Now fresh handles
either shape so callers use whichever they have.

## fresh 0.19.0

Decompose
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
into composable pieces; rename `frs_habitat_known()` →
[`frs_habitat_overlay()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.md).
Pre-1.0, breaking changes accepted to set the right shape before
external use.

- New exported `frs_habitat_predicates(sp_params)` — pure-R helper that
  takes a single species’ params and returns a named list of SQL boolean
  predicates (`spawn`, `rear`, `lake_rear`, `wetland_rear`) ready to
  embed in `CASE WHEN <pred> THEN TRUE ELSE FALSE END`. Extracted from
  [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)’s
  per-species loop. Testable without a DB; 33 unit tests cover both
  rules-YAML and CSV-ranges paths, edge_type filters, and the
  lake/wetland W-rule gating.
- [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  shrinks from 551 → ~447 lines and gains a `known = NULL` parameter —
  when supplied, calls
  [`frs_habitat_overlay()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.md)
  automatically as a post-step. Rule-based classification + observation
  overlay can now be a single call.
- **Breaking:** `frs_habitat_known()` renamed to
  [`frs_habitat_overlay()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.md).
  The mechanism is overlay (additive OR-in); “known” presupposed
  provenance the function doesn’t enforce. No deprecation alias —
  pre-1.0, no external users.

## fresh 0.18.0

- New
  [`frs_habitat_overlay()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.md)
  — stitches known-habitat boolean flags from a wide-format lookup table
  INTO an existing `streams_habitat` classified by
  [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md).
  Mirrors the bcfishpass blend of model output (`habitat_linear_<sp>`)
  with manual / observation-based knowns (`streams_habitat_known`) into
  the published `streams_habitat_linear` integer encoding. Purely
  additive (`FALSE → TRUE` only). Per-species columns
  `{habitat}_{species_lower}` matched against the species code in
  `streams_habitat`; missing per-species columns skip with a verbose
  message rather than erroring. Compound join key parameterisable via
  `by` (default `c("blue_line_key", "downstream_route_measure")`).
  Surfaced as a need in
  [link#55](https://github.com/NewGraphEnvironment/link/issues/55) —
  link’s pipeline loaded `user_habitat_classification.csv` for
  break-points + barrier overrides but never propagated its flags into
  `fresh.streams_habitat`. After this lands, link’s
  `lnk_pipeline_classify` can call
  [`frs_habitat_overlay()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.md)
  as a post-step.

## fresh 0.17.1

- Params validator accepts `wetland_ha_min` predicate on rear rules with
  `waterbody_type: W` — mirrors the existing `lake_ha_min` /
  `waterbody_type: L` rule. The classifier in 0.17.0 already read
  `wetland_ha_min` from rear rules to filter the fwa_wetlands_poly join;
  the validator predicate allowlist hadn’t been extended so rules YAML
  with the key was rejected. Surfaced in
  [link#51](https://github.com/NewGraphEnvironment/link/issues/51) when
  `lnk_rules_build()` started emitting `waterbody_type: W` rules with
  the threshold.

## fresh 0.17.0

- [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  now honours the `waterbody_type: L` / `waterbody_type: W` entries
  under a species’ `rear:` rules in the rules YAML. Previously the
  `lake_rearing` / `wetland_rearing` booleans were set whenever a
  segment fell in the species’ rear channel-width window and matched a
  lake/wetland `waterbody_key` — regardless of whether the species had a
  lake/wetland rear rule declared. Now the flag is `FALSE` unless the
  species has the matching rule, and the rule’s optional `lake_ha_min` /
  `wetland_ha_min` threshold filters the polygon join to exclude
  waterbodies below that area
  ([\#165](https://github.com/NewGraphEnvironment/fresh/issues/165)).
  Surfaced in link#51 when every species in link’s bcfishpass and
  default bundles produced bit-identical `lake_rearing_ha` totals
  despite the bundles declaring different rear rules.

## fresh 0.16.0

- [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  output schema gains a `wetland_rearing` boolean column, mirroring
  `lake_rearing` but joined to `whse_basemapping.fwa_wetlands_poly` on
  `waterbody_key`
  ([\#164](https://github.com/NewGraphEnvironment/fresh/pull/164)).
  Additive schema change — existing callers are unaffected;
  `lake_rearing` semantics unchanged. Prerequisite for link’s compound
  rearing rollup (link#51).

## fresh 0.15.0

- Remove unused `frs_fish_habitat()` and `frs_fish_obs()`. Both were
  BC-specific fetchers hard-coded to bcfishpass/bcfishobs table names
  and had no callers in fresh or link. If BC-specific fetchers become
  useful later they belong in link where the domain context lives
  ([\#162](https://github.com/NewGraphEnvironment/fresh/pull/162))
- Exported function count: 41 → 39.
- Add missing `@param barrier_overrides` docstring on
  [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  — the parameter was already in the signature but absent from roxygen
  so the rendered help didn’t describe link’s main integration point.
- Docs role-clarity refresh: README + CLAUDE.md ecosystem tables updated
  to describe link’s full scope; pipeline wording split into
  fish-habitat (link → fresh) and land-cover-change (fresh → flooded →
  drift); CLAUDE.md version + architecture file list brought current.

## fresh 0.14.0

- Add
  [`frs_barriers_minimal()`](https://newgraphenvironment.github.io/fresh/reference/frs_barriers_minimal.md)
  — reduce barrier points to the downstream-most per flow path via
  `fwa_upstream()` self-join. Extracts the bcfishpass “non-minimal
  removal” pattern from link’s compare pipeline into a reusable fresh
  function. Typical reduction ~27,000 raw gradient barriers → ~700
  minimal on a full watershed group
  ([\#160](https://github.com/NewGraphEnvironment/fresh/issues/160))

## fresh 0.13.8

Three-phase cluster connectivity for rearing.

- Phase 1: on-spawning segments (both rearing AND spawning) excluded
  from clustering — always valid. Prevents over-removal of rearing on
  spawning streams
  ([\#153](https://github.com/NewGraphEnvironment/fresh/issues/153))
- Phase 3: `FWA_Downstream()` on the broken streams table (mainstem
  only) replaces `fwa_downstreamtrace()` on raw FWA. Finds spawning
  downstream of rearing clusters with path gradient + distance
  constraints
  ([\#153](https://github.com/NewGraphEnvironment/fresh/issues/153))
- BULK CH rearing +6.0% → +2.6%, BT rearing +1.3% → -2.2%. All species
  within 5% across 4 WSGs

## fresh 0.13.7

Apply bridge gradient along downstream path in `frs_cluster`.

- [`frs_cluster()`](https://newgraphenvironment.github.io/fresh/reference/frs_cluster.md)
  downstream check now applies `bridge_gradient` and `bridge_distance`
  segment-by-segment along the `fwa_downstreamtrace` path. Upstream
  check remains boolean — `FWA_Upstream` returns tributaries that
  interleave with mainstem in `row_number()` ordering, making path
  gradient unreliable on branching networks
  ([\#153](https://github.com/NewGraphEnvironment/fresh/issues/153))

## fresh 0.13.6

Support `spawn_connected` rules for waterbody-adjacent spawning.

- Parse `spawn_connected` block in rules YAML — permissive spawn
  thresholds for segments in the downstream trace from waterbody
  outlets. Own validation separate from spawn/rear rules
  ([\#154](https://github.com/NewGraphEnvironment/fresh/issues/154))
- Additive step in `.frs_connected_waterbody()`: accessible segments in
  the trace meeting `spawn_connected` thresholds get `spawning = TRUE`
  even if they failed standard classification. BULK SK spawning -9.6% to
  -0.7% vs bcfishpass
  ([\#154](https://github.com/NewGraphEnvironment/fresh/issues/154))

## fresh 0.13.5

Fix lake outlet ordering and extract reusable downstream trace.

- Fix multi-BLK lake outlet selection: use `wscode_ltree` network
  topology instead of `downstream_route_measure` (meaningless across
  BLKs). BULK SK spawning -22.6% to +0.1% vs bcfishpass
  ([\#147](https://github.com/NewGraphEnvironment/fresh/issues/147))
- Fix cumulative distance partitioning: partition by `waterbody_key`
  instead of `blue_line_key` so distance accumulates per lake, not per
  BLK ([\#147](https://github.com/NewGraphEnvironment/fresh/issues/147))
- Extract `.frs_trace_downstream()` — reusable downstream trace with
  distance cap and gradient stop
  ([\#147](https://github.com/NewGraphEnvironment/fresh/issues/147))
- Rename `.frs_connected_spawning()` to `.frs_connected_waterbody()` —
  parameterized for any waterbody type
  ([\#147](https://github.com/NewGraphEnvironment/fresh/issues/147))
- `waterbody_type: L` now includes reservoirs
  (`fwa_manmade_waterbodies_poly`) via shared `.frs_waterbody_tables()`
  helper — the FWA table split is digitization origin, not ecology
  ([\#147](https://github.com/NewGraphEnvironment/fresh/issues/147))

## fresh 0.13.4

Index input tables for standalone `frs_habitat_classify` performance.

- [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  now indexes input tables before the access gating loop — 35x speedup
  when called directly (bypassing `frs_habitat`)
  ([\#150](https://github.com/NewGraphEnvironment/fresh/issues/150))
- `.frs_index_working()` is now idempotent with `IF NOT EXISTS` — safe
  to call multiple times on the same table
  ([\#150](https://github.com/NewGraphEnvironment/fresh/issues/150))

## fresh 0.13.3

Two-phase connected spawning and multi-label breaks.

- Two-phase connected spawning for lake-rearing species (SK, KO)
  matching bcfishpass v0.5.0: downstream trace from lake outlets (3km
  cap, gradient stop) + upstream cluster with lake polygon proximity
  (`ST_DWithin`). Auto-dispatched when rearing rules include
  `waterbody_type: L`
  ([\#147](https://github.com/NewGraphEnvironment/fresh/issues/147))
- Multiple labels per break position preserved — a gradient_15 and a
  falls at the same measure both survive in `streams_breaks`
  ([\#145](https://github.com/NewGraphEnvironment/fresh/issues/145))

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
  classification) parallelize via `furrr::future_map()` when
  `workers > 1`
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
