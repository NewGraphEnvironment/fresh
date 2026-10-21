# Task: Inherit `near_river` from the thresholds CSV: a measure per stage, a per-rule opt-out (#263, with #262)

**If done:** a species' near-river rule lives in `parameters_habitat_thresholds.csv` beside its gradient, width and MAD ranges, per stage, with the measure of "a river" chosen there (discharge, channel width or stream order, #262), and applies to every rule that inherits thresholds and has a size test; a rule opts out with `near_river: false` or overrides with its own mapping. Consumer: NewGraphEnvironment/link#364 (Phase 0 of its approved plan, 2026-10-21).

## Decided at the gate (link#364 plan gate, operator + agent, 2026-10-21)

- One PR for #262 and #263; link pins the release carrying both.
- Rule mapping names exactly one size key: `discharge_min`, `channel_width_min` or `stream_order_min`, plus `distance_max`. The loader normalizes it to `(measure, threshold, distance_max)`.
- CSV columns per stage: `<stage>_river_measure` (`discharge` / `channel_width` / `stream_order` / `model`; absent or NA = `model`), `<stage>_river_discharge_min`, `<stage>_river_channel_width_min`, `<stage>_river_stream_order_min`, `<stage>_river_distance_max`. They are stored in `params[[sp]]$near_river$<stage>`, a sibling of `ranges`.
- Agent's calls (mechanism, stated here): under `model` both `_channel_width_min` and `_discharge_min` must be set when `distance_max` is, so neither model is silently pair-less. `frs_near_river()` takes `threshold`, `distance_max` and `measure` (breaking from 0.41.0, released the same day with no external caller). The output table carries `measure` and `threshold` in place of `discharge_min`, and an output table in the 0.41.0 shape stops with a message to drop it. Predicates are built only for the models applied (cw is skipped when every group is mad), and the walk's pairs come from those models.

## Phase 1 — the measure (#262)
- [x] `frs_near_river(conn, table, to, threshold, distance_max, measure = "discharge", verbose)`: walk SQL parameterized on the measure's column (`mad_m3s` / `channel_width` / `stream_order`); origins NULL or below, targets at or above; output `(id_segment, watershed_group_code, measure, threshold, distance_max, dist_m)`; old-shape table stops; columns checked per measure
- [x] Rule grammar: `.frs_validate_near_river()` takes exactly one size key, or `false` (refused on L/W), refuses `true`; loader normalizes; `.frs_near_river_sql()` matches measure, threshold, distance
- [x] Tests: walk by width and by order on the fixture; predicate text; validator cases; existing tests moved to the new names

## Phase 2 — inheritance (#263)
- [x] `frs_params()`: `*_river_measure` in `char_fields`; `.frs_build_near_river()` per stage (half pairs stop incl. `Inf`; unknown measure stops; `model` needs both mins); warn on unknown `*_river_*` columns
- [x] `.frs_rule_inherits()`, `.frs_rule_size_parts()` extracted from `.frs_rule_to_sql()`; `.frs_rule_near_river()` resolves explicit → `false` → inherited when the rule inherits and has a size part; `.frs_stage_inherit()` / `.frs_stage_rules()` shared by `frs_habitat_predicates()` and `.frs_near_river_specs(params, species, models)`
- [x] `frs_habitat_classify()`: specs after the `params_fresh` filter, over the applied models; column check per measure; cw predicates only when used; roxygen
- [x] Bundled thresholds CSV gains the ten columns as NA
- [x] Tests: each measure and `model` under cw and mad; override; opt-out; no-op on `thresholds: false`; refusals; NA columns compile every bundled rule byte-identically; specs equal effective pairs (inherit / override / opt-out → two walks); no size part → no pair; mad species with no range reads `(FALSE OR EXISTS)`; the R rule's form; half pairs; yaml round trip of `false`

## Phase 3 — live check, docs, release
- [x] Live check by width and order: `data-raw/near_river_measure_check.R` (equivalence with the discharge walk on a relabelled copy, since the independent reference reads discharge only and lives outside the repo); BULK run logged, 0 rows apart for both measures. `near_river_check.R` updated to the new argument names.
- [ ] Docs at the places #263 lists; NEWS; `devtools::document()`; `devtools::test()`; `lintr`; `pkgdown::check_pkgdown()`
- [ ] `/code-check branch`; `/planning-archive`; `/gh-pr-push`

## Validation
- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verified by the suite, the byte-identity test over every bundled rule, and the live BULK check.
