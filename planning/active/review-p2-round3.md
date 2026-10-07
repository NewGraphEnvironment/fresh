# Code-check round 3 — fresh#240 phase 2 (staged diff: R/frs_params.R, tests/testthat/test-frs_params.R)

## Clean

No issues found in the staged diff.

### What was checked

**Validator ordering and types (`.frs_validate_rule`)**
- The new rear block (lines 373-393) runs after the generic `requires_connected` check (343-352) and the `connected_distance_max` check (354-367). So `cdm` is already known to be a numeric scalar, or NULL, when `is.finite(cdm)` runs. The cases:
  - absent or `~` (NULL) gives the intended error;
  - `.inf` passes `is.numeric`, then fails `is.finite`;
  - `.nan` gives NaN, which also fails `is.finite`;
  - `0` and `-5` fail `<= 0`.
- No `if()` sees a length-0 or NA condition.

**Spawn behaviour.** The new block is gated on `habitat == "rear"`. `spawn_connected` is skipped before the rule loop. So a spawn `requires_connected: rearing` with no distance still loads, and the SK test pins that.

**`.frs_validate_rear_connected`**
- Every element of `rule_list` has already passed `is.list(rule)`.
- It matches with `identical(r[["waterbody_type"]], wt)`, the same predicate `.frs_find_waterbody_rule()` (R/utils.R:380) uses. So "first" means the same thing in both places.
- It is called once per rear block, after the per-rule loop.

**Tests.** Each `expect_error` regex was traced against the message the validator actually produces. All four match:
- the rearing-value error;
- the L/W error, in both cases;
- the distance error, in all four cases;
- the second-L-rule error, including the escaped parentheses.

The second-L-rule fixture passes per-rule validation, so the error comes from the placement validator, as intended.

### Mechanism sweep: "the first L/W rear rule is the one that is read"

Every reader of a rear rule's keys in fresh `R/` and link `R/`:

| Reader | What it reads | Agrees with the validator? |
|---|---|---|
| `frs_habitat_predicates.R:205-206` (`build_wb_pred`) | first L / first W, via `.frs_find_waterbody_rule()`; reads `*_ha_min` | yes |
| `frs_habitat.R` bucket pass (unstaged, out of scope) | first L / first W, via `.frs_find_waterbody_rule()`; reads `requires_connected` and `connected_distance_max` | yes, same lookup |
| `frs_habitat.R:1224-1235` (SK spawn connectivity) | first rule of L **or** W, whichever comes first; reads `lake_ha_min` only | does not read `requires_connected`, so no disagreement |
| `frs_habitat_predicates.R` main `rear` predicate | all rules where `area_only` is not TRUE, via `.frs_rules_to_sql` | does not read `requires_connected`, so the `rearing` flag is not gated (by design) |
| link `lnk_pipeline_classify.R:170` | first rear rule with `channel_width_min_bypass` | unrelated key |
| link `lnk_habitat_validate.R` / `lnk_compare_*` | fresh predicates and persisted bucket columns | none reads `requires_connected` |

No reader would disagree with these validators. The one known cross-repo hazard is link `lnk_rules_build()` stamping `rear_requires_connected` (and `rear_connected_distance_max`). It is accepted and tracked in link#310.
