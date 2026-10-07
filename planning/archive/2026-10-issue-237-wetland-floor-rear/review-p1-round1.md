# Review: Phase 1 tests (#237), round 1

## Clean

No issues found.

## What was checked

- **Fail on current code, for the claimed reason.** I ran all four files against the current code. The new blocks fail or error, and the pre-existing blocks all pass:
  - `test-frs_params.R`: the W-floor test fails because there is no `WHERE`. The wrong-key test fails on its `W` + `lake_ha_min` half, because the current code applies the floor. The no-floor pin passes.
  - `test-utils.R`: `.frs_rule_ha_min` errors because the helper does not exist yet.
  - `test-frs_habitat_predicates.R`:
    - rear: 4 of 6 expectations fail. These are the `rear` regex and the `fwa_wetlands_poly)` absence check, under both `cw` and `mad`. `wetland_rear` already passes.
    - spawn: fails.
    - bundled: 6 of 13 fail. That is one `rear` assertion per species, with `n_checked = 6`, so the loop is not empty.
  - `test-frs_habitat.R`: the connectivity test fails with `c(200, 50, 200)` against an expected `c(1.5, 50, 200)`.
- **Pass after a correct fix.** I applied a minimal version of the planned fix to a scratch copy of the repo:
  - `.frs_rule_ha_min()` returns `NULL` for no type, R, a mismatched key, or `NA`.
  - `.frs_rule_to_sql()` and the floor in `.frs_run_connectivity()` both call it.

  All four files then passed with 0 failures and 0 errors. `build_wb_pred()` was left unchanged and still passes, so these tests do not force that refactor. The plan does not depend on that.
- **Mock is reached.** The `.frs_connected_waterbody` mock records 3 calls, one per species and in loop order. `cluster_rearing = FALSE` keeps execution out of the `cluster_*` columns the fixture omits. Every species has an L or W rear rule, so the `frs_cluster` stop-mock is never reached. No rear rule carries `requires_connected`, so the bucket pass never calls the unmocked `.frs_bucket_connected`. The `<<-` writes to the `calls` variable in the test environment. If the mock were never called, `vapply` would return `numeric(0)` and the test would fail.
- **Regexes do not match the old output.**
  - `fwa_wetlands_poly WHERE area_ha >= 1\.5` cannot match the old unfiltered subquery.
  - `fwa_wetlands_poly\)` is a valid negative check. After the fix the closing paren follows the `WHERE` clause.
  - The bundled loop uses `fixed = TRUE` with `.frs_sql_num()` output, and the 0.5 floor matches exactly.
- **Wrong-key contract.** The loader (`R/frs_params.R:256-285`) rejects `lake_ha_min` without `waterbody_type: L`, and `wetland_ha_min` without `W`. The bundled YAML has no cross-keyed rules, and no existing test depends on a `W` rule taking its floor from `lake_ha_min`. Dropping the cross-key floor therefore breaks nothing.
- **Bundled YAML.** It has 6 `W` rear rules (BT, CH, CO, ST, WCT, RB), and none carry `area_only`. The `area_only` filter on the main `rear` predicate therefore cannot make the bundled test fail even after a correct fix.
- **Checklist items.**
  - No `expect_gt(..., info =)`. `expect_gt(n_checked, 0L)` has no `info` argument.
  - No `expect_snapshot` regression nets.
  - No skips gate the new blocks.
  - New code reads rules with `[[`, not `$`.
  - No `%||%`.
