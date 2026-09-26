# Task: Phase 2: enrich streams with mad_m3s and add mad predicate to rule evaluator (#114)

Habitat eligibility rules (#113 Phase 1) cannot evaluate `mad` (mean annual discharge) predicates because the segmented streams table produced by `frs_network_segment()` does not carry a `mad_m3s` column.

## Context

Rules YAML (#113 Phase 1) can't express MAD (mean annual discharge) predicates. Segmented streams have no `mad_m3s` column, and `.frs_validate_rule()` rejects `mad:` on purpose (`R/frs_params.R:182`). Exploration showed:

- `whse_basemapping.fwa_stream_networks_discharge` exists in fwapg (`linear_feature_id`, `mad_m3s`; 2.7M rows, about 26% NULL `mad_m3s`).
- `frs_params()` already parses the CSV `*_mad_min/max` columns into `ranges$*$mad_m3s` (`.frs_build_ranges()`), but nothing uses them.
- The bundled `parameters_habitat_method.csv` (bcfishpass `example_newgraph`) sets all 187 WSGs to `cw`, and fresh doesn't read it.

**Decision (user): rules-explicit only (issue Option B).** MAD applies only when a rule says `mad: [min, max]`. CSV MAD ranges stay parsed but are **not** inherited or applied, so existing outputs don't change. A per-WSG cw/mad model switch will be filed as a follow-up issue.

## Phase 1: Tests first
- [x] `test-frs_params.R`: replace ".frs_load_rules errors on mad predicate" with (a) `mad: [0.164, 9999]` validates OK and (b) malformed `mad` errors: non-numeric, length ≠ 2, min > max
- [x] `test-utils.R`: `.frs_rule_to_sql(list(mad = c(0.164, 9999)))` gives `s.mad_m3s BETWEEN 0.164 AND 9999`; `mad` composes with `edge_types` and inherited gradient/cw; a rule without `mad` does **not** inherit CSV MAD even when `csv_thresholds$mad_m3s` is present
- [x] `test-frs_habitat_predicates.R`: CO CSV-only path (no rules) has no `mad_m3s` in any predicate (regression guard for Option B); a rules path with a `mad:` rule has `s.mad_m3s` in the spawn/rear predicate
- [x] DB integration (skip if no DB): `frs_network_segment()` output has a numeric `mad_m3s` column, populated for a small ADMS AOI

## Phase 2: Enrich segmented streams with mad_m3s
- [x] `R/frs_network_segment.R:147`: add a parallel `frs_col_join(conn, to, from = "fwa_stream_networks_discharge", cols = "mad_m3s", by = "linear_feature_id")` next to the channel_width join
- [x] `R/frs_habitat.R:818` (base table build): same join, so both pipelines carry `mad_m3s`
- [x] Update the roxygen on `frs_network_segment()` that describes output columns to mention `mad_m3s` (NULL where the source has no MAD)

- [x] (code-check) `.frs_persist_columns()`: `to_streams` persist aligns columns by name/type, so adding `mad_m3s` doesn't break tables persisted by older runs

## Phase 3: `mad` predicate in rule validator + evaluator
- [x] `R/frs_params.R`: remove the Phase-1 `mad` stop; add `"mad"` to `valid_predicates`; validate numeric length-2 with min ≤ max (same message style as `lake_ha_min`); update the roxygen predicate list and `.frs_validate_rule` docs
- [x] `R/utils.R` `.frs_rule_to_sql()`: `if (!is.null(rule[["mad"]]))` → `s.mad_m3s BETWEEN %s AND %s` via `.frs_sql_num()`. No CSV inheritance branch (document why: cw vs mad is a per-WSG model choice). Update the `@param rule` docs
- [x] Document the NULL semantics: segments with NULL `mad_m3s` fail a `mad:` rule (BETWEEN on NULL → not TRUE)
- [x] `frs_habitat_predicates()` roxygen: note that CSV MAD ranges are parsed but only applied through explicit `mad:` rules
- [x] `devtools::document()`, `lintr::lint_package()`

## Phase 4: Verify + follow-up
- [ ] Full `devtools::test()` (local fwapg override, per CLAUDE.md)
- [x] Spot-check on a real sub-basin: a rules YAML with `mad:` for CO gives a strict subset of the no-`mad` spawning segments; no rules gives output identical to main (no-op)
- [x] File a follow-up issue (#220): per-WSG `model` (cw|mad) switch reading `parameters_habitat_method.csv`, mirroring bcfishpass
- [ ] NEWS.md entry (version bump at merge via `/gh-pr-merge`)

## Validation
- [ ] Tests pass
- [x] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Critical files
`R/frs_network_segment.R`, `R/frs_habitat.R`, `R/frs_params.R`, `R/utils.R`, `R/frs_habitat_predicates.R`, `tests/testthat/test-{frs_params,frs_habitat_predicates,frs_habitat}.R`
