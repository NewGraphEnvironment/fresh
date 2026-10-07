# Code-check review — fresh#240 phase 2, round 2 (staged diff only)

## Clean

No issues found.

What was checked:
- `.frs_validate_rear_connected()` matches with `identical(r[["waterbody_type"]], wt)`,
  the same predicate `.frs_find_waterbody_rule()` (R/utils.R:380-387) uses, so "first L /
  first W rule" means the same rule in validator and reader. Called only after every
  rule in the block has passed `.frs_validate_rule()` (non-mapping rules already
  errored), so the `vapply` cannot meet a non-list element.
- Rear-only gate in `.frs_validate_rule()` runs after the generic `requires_connected`
  / `connected_distance_max` shape checks, so `wt` is a validated character scalar and
  `cdm` a numeric scalar when `is.finite()` / `<= 0` run; NaN / Inf / absent all stop.
- Spawn path untouched: the new checks are gated on `habitat == "rear"`, and HEAD's
  `.frs_run_connectivity()` reads `requires_connected` from spawn rules only. The
  bundled `inst/extdata/parameters_habitat_rules.yaml` carries `requires_connected`
  only on spawn rules (lines 149-156, 247-254).
- No HEAD test or shipped YAML puts `requires_connected` on a rear rule
  (`git grep` over HEAD `tests/`, `inst/`).
- `NOT_CRAN=true` `test_file("tests/testthat/test-frs_params.R")`: FAIL 0 / PASS 164 /
  SKIP 2 (DB-gated). Note: `load_all()` picked up the unstaged `R/frs_habitat.R`; the
  params tests do not touch it.

Accepted tradeoffs (link's `add_rc()` stamping, YAML edge cases from round 1) not re-flagged.
