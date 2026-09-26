# Task: Per-WSG cw/mad habitat model switch from parameters_habitat_method.csv (#220)

## Problem

#114 added a `mad: [min, max]` rule predicate and joined `mad_m3s` onto segmented streams. MAD only applies where a rules YAML asks for it explicitly: CSV MAD thresholds (`spawn_mad_min`, `rear_mad_min/max`, parsed by `frs_params()` into `ranges$*$mad_m3s`) are never applied or inherited.

bcfishpass uses channel width **or** MAD, chosen per watershed group through `parameters_habitat_method.csv` (`model = cw | mad`). fresh bundles that CSV (`inst/extdata/parameters_habitat_method.csv`) but never reads it. The bundled `example_newgraph` copy sets all 187 WSGs to `cw`, so nothing changes today. A config that sets `mad` for some WSGs would not be honoured.

## Phase 1: Tests first (failing)
- [x] `test-frs_habitat_predicates.R`: `model = "mad"` CSV path emits `s.mad_m3s BETWEEN` for spawn/rear and no `channel_width`; `model = "cw"` is unchanged (update the existing "does not apply mad" test to be cw-scoped)
- [x] predicates: rules path under `mad` inherits the MAD range. An explicit rule `mad:` overrides it; rule-level `channel_width:` is dropped under `mad` (bundled R-rule river bypass is cw-only, per bcfishpass). `thresholds: false` and `L`/`W` rules don't inherit it
- [x] predicates: species with NA MAD under `mad` → spawn/rear size predicate `FALSE`; lake/wetland rearing use the rear MAD window, or polygon membership only when the species has no rear MAD window (SK/KO keep lake rearing)
- [x] `test-frs_params.R` (where the `.frs_rule_to_sql()` tests live): MAD inheritance cases, including the NA-range → `FALSE` sentinel; rewrite the #114 "does not inherit mad" test
- [x] `test-utils.R`: unit tests for the new pure helpers: WSG→model resolution (missing → cw, invalid → error) and the mixed-model CASE combiner
- [x] Integration (`test-frs_habitat_classify.R`): one WSG with MAD coverage run under `params_method` = mad vs cw. Spawning counts differ, and the mad count matches a direct SQL count on `mad_m3s`. Direct `frs_habitat_classify(gate = FALSE)` on the CSV path (not `frs_habitat()`, whose gating + connectivity would skew counts); ADMS sub-basin (local fwapg: 10,449 / 11,520 segments have MAD). Missing `mad_m3s` column → error

## Phase 2: Predicate + rule SQL
- [x] `.frs_rule_to_sql()`: MAD inheritance from `csv_thresholds$mad_m3s` (`c(NA, NA)` sentinel → `FALSE` part for inheriting rules); update the roxygen `@param rule` / `csv_thresholds` docs
- [x] `frs_habitat_predicates()`: add a `model` arg; size-dimension selection on both paths plus lake/wetland; rewrite the "CSV MAD ranges are not applied" doc paragraph

## Phase 3: Per-WSG resolution in classify + thread through frs_habitat
- [ ] Internal helpers in `R/utils.R`: `.frs_habitat_models(wsg_codes, params_method)` and `.frs_preds_by_model()` (CASE combiner)
- [ ] `frs_habitat_classify()`: `params_method` param (after `params_fresh`, NULL default → bundled CSV; validate columns, model values, duplicate WSGs), `mad_m3s` column guard via `.frs_table_columns()` run before indexing/DELETE, per-model predicates
- [ ] `frs_habitat()`: `params_method` param, passed on the sequential `.run_job` path and the mirai `mirai_map` path (`R/frs_habitat.R` ~L451, ~L614, and the `mirai_map` `...` args ~L675)
- [ ] `devtools::document()`; runnable/`\dontrun` examples updated

## Phase 4: Docs + release
- [ ] NEWS.md entry: NA-MAD species behaviour, R-rule channel_width dropped under mad, SK/KO lake rearing, `BETWEEN` vs bcfishpass strict `>`, `stream_order >= 8` bypass not implemented, `frs_habitat_partition()`/`frs_habitat_species()` not model-aware, link follow-up
- [ ] Full `devtools::test()` + `lintr::lint_package()` clean
- [ ] Final commit: bump DESCRIPTION version (0.34.0 → 0.35.0)

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
