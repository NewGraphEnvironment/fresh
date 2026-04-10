# Task: Habitat eligibility rules format (issue #113, Phase 1)

## Goal

Add a YAML-based rules format for species habitat eligibility that can express multi-rule species (SK lake-only, CO wetland carve-out, BT/CO river-polygon spawning) without code changes. Phase 1 — no MAD support (that's #114).

## Status: in progress

## Why this matters

The CSV format `parameters_habitat_thresholds.csv` assumes one rule per habitat type. bcfishpass species need:
- SK rear: `waterbody_type=L AND area_ha >= 200`, no stream rearing
- CO rear: stream rule OR wetland-flow rule (`edge_type IN (1050, 1150)`) with NO threshold checks
- All anadromous: spawn includes river polygons via `waterbody_type=R`

The rules YAML adds the missing OR + per-rule threshold opt-out semantics.

## Phases

### Phase 0: Workflow setup
- [x] Branch `113-habitat-rules-phase-1` created
- [x] Initialize PWF files
- [x] First commit: PWF init only

### Phase 1: Bundled YAML + Imports
- [x] Create `inst/extdata/parameters_habitat_rules.yaml` (link-generated default)
- [x] Add `yaml` to `DESCRIPTION` Imports
- [x] Commit + PWF update + code-check

### Phase 2: Parser in frs_params
- [x] Add `rules_yaml` parameter to `frs_params()` (default = bundled file, NULL = no rules)
- [x] Parse YAML, attach `params[[sp]]$rules$spawn` and `$rules$rear` per species
- [x] Validate predicates: error on `mad` (Phase 2/#114), unknown keys, `lake_ha_min` without `waterbody_type: L`
- [x] Tests in `test-frs_params.R`
- [x] Commit + PWF update + code-check

### Phase 3: Rule evaluator helpers in utils.R
- [x] `.frs_rule_to_sql(rule, csv_thresholds)` — single rule → AND predicate
- [x] `.frs_rules_to_sql(rules, csv_thresholds)` — list of rules → OR predicate
- [x] Threshold inheritance via `csv_thresholds` arg, opt-out via `thresholds: false`
- [x] Unit tests for each predicate type
- [x] Commit + PWF update + code-check

### Phase 4: Rule evaluator wired into classify
- [x] `frs_habitat_classify()` checks for `params_sp$rules$spawn`/`$rear` and uses evaluator
- [x] Falls through to existing `$ranges` logic when no rules
- [x] `lake_rearing` column logic UNCHANGED
- [x] Commit + PWF update + code-check

### Phase 5: Wire through frs_habitat
- [x] Add `rules` parameter (default NULL = bundled YAML, string = custom path, FALSE = disable)
- [x] Only consulted when `params` is NULL
- [x] Update roxygen example (custom path + disable)
- [x] Commit + PWF update + code-check

### Phase 6: Integration tests on ADMS sub-basin
- [x] SK rear streams = 0 (only lake_rearing, lakes >= 200 ha)
- [x] CO rear includes wetland-flow segments regardless of thresholds
- [x] PK `rear: []` → all rearing FALSE
- [x] Backward compat: `rules = FALSE` runs CSV-only path
- [x] `lake_rearing` column preserved with rules
- [x] Commit + PWF update + code-check

### Phase 7: Verify and PR
- [ ] `devtools::test()` all pass
- [ ] `devtools::document()` clean
- [ ] `lintr::lint()` on changed files
- [ ] Push branch
- [ ] PR with SRED tag

### Phase 8: Merge + archive
- [ ] Merge `--admin --delete-branch`
- [ ] Bump DESCRIPTION 0.11.1 → 0.12.0 + NEWS.md
- [ ] Archive PWF to `planning/archive/2026-04-issue-113-habitat-rules-phase-1/`
