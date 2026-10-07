# Task: Lake and wetland rearing buckets: size by polygon area, require connected spawning (#240)

**If done:** `lake_rearing` and `wetland_rearing` mean "an accessible lake or wetland big enough for the species, connected to its spawning". Lake and wetland hectares then measure habitat the species can use. **If never:** they count every accessible polygon above an area floor whose centreline happens to pass a stream-size test. That includes polygons with no connection to the species' spawning, and the gate is the inflow's size, not the lake's.

`build_wb_pred()` (`R/frs_habitat_predicates.R:194`) gates the buckets on polygon area and on the size of the line through the polygon (width under `cw`, `mad_m3s` under `mad`; under `cw` a species with no rear width range gets `FALSE`). Connectivity never reaches the buckets: `.frs_run_connectivity()` clusters only `rearing` and `spawning`.

## Decisions (approved at the plan gate, 2026-10-06)

1. **Distance semantics: network distance, both directions, no gradient bridge.** A polygon is connected if (a) same-species spawning lies on one of its own lines, or (b) a downstream trace from the polygon's outlet reaches spawning within D, or (c) a downstream trace from a spawning cluster's lowest point reaches any line of the polygon within D. Both traces reuse `.frs_trace_downstream()` (mainstem convention). No gradient stop.
2. **`connected_distance_max` is required** on a rear L/W rule with `requires_connected` (fail loud at rules load).
3. **`requires_connected` on a rear rule is valid only on `waterbody_type: L|W`, value `spawning`.** Anything else on a rear rule errors at load.
4. **Area-only is unconditional**: every bundle's buckets move on upgrade, under `cw` too. Connectivity is opt-in. Minor bump at merge (0.37.0).
5. **Out of scope, noted only:** the legacy non-rules path at `R/frs_habitat.R:1133`, and the bucket using `fwa_lakes_poly` without reservoirs.

## Phase 1: Area-only bucket predicates
- [x] Tests first: L/W bucket has no `channel_width` / `mad_m3s` under `cw` and `mad`; a species with an L rule and no rear size range gets the area predicate (not `FALSE`) under both models; replace the tests at `test-frs_habitat_predicates.R:172` and `:362-378`
- [x] `build_wb_pred()`: drop the size clause and the `cw` "no width range → FALSE" branch; keep rule-presence gating and `*_ha_min`
- [x] Update `frs_habitat_predicates()` roxygen + `devtools::document()`

## Phase 2: Rule validation for rear-bucket connectivity
- [x] Tests first (`test-frs_params.R`): rear L/W rule with `requires_connected: spawning` + `connected_distance_max` loads; rear rule without `waterbody_type` L/W errors; rear `requires_connected: rearing` errors; missing `connected_distance_max` errors; spawn-block behaviour unchanged
- [x] Extend `.frs_validate_rule()` (`R/frs_params.R:313-335`) with the rear-only checks

## Phase 3: Bucket connectivity filter
- [x] Let `.frs_trace_downstream()` optionally carry `origin_id` into the target and take `gradient_max = NULL` (no stop); existing SK caller byte-identical (SQL-capture test)
- [x] New `.frs_bucket_connected(conn, table, habitat, species, column, distance_max)`: polygon unit via `s.waterbody_key`; connected set = own-line spawning ∪ outlet trace ∪ spawning-cluster trace; `UPDATE ... SET <column> = FALSE` for the species' bucket rows whose `waterbody_key` is not in it; verbose before/after counts
- [x] Wire into `.frs_run_connectivity()` after the spawning block, once per L / W rule carrying `requires_connected: spawning`
- [x] DB tests on a synthetic network (pg_temp streams + habitat with fabricated ltrees, `skip_if_no_conn()`): lake on a sub-threshold inflow keeps its bucket; disconnected lake loses it; lake beyond D loses it; one connected line keeps the whole polygon; rule without `requires_connected` unchanged
- [x] Restore-the-bug check: disable the UPDATE / the distance cap and confirm the disconnected / beyond-D tests go red

## Phase 4: Live check, docs, release prep
- [x] Live check on local fwapg, NATR and PARS BT (link's persisted `fresh_default` + link `default` rules; connectivity at 0.5 / 1 / 3 / 10 km): `data-raw/bucket_connected_check.R`, evidence in `data-raw/logs/bucket_connected_240/`
- [x] NEWS entry drafted in the PR body (behaviour change for every bundle; connectivity opt-in keys). fresh writes NEWS.md in the release commit (`/gh-pr-merge`), so NEWS.md is untouched here; no version bump
- [x] `devtools::test()` FAIL 0 / PASS 1201 (3 warnings, all pre-existing in `test-frs_network_features-live.R`). `devtools::check()` result identical to `main`'s: the same 12 `test-frs_network_features.R` failures (no `tibble` in the check library), and the same 5 warnings and 3 notes; the branch passes 49 more tests. lintr: on changed lines, only `indentation_linter` on the codebase's `sprintf("SQL")` layout (about 175 of the same in `main`'s `frs_habitat.R`)

## Validation

- [x] Tests pass (see the sweep above)
- [x] `/code-check` on each code commit: P1 3 rounds, P2 3 rounds, P3 2 rounds + an 11-mutation enumeration (`review-p*-round*.md`)
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion
