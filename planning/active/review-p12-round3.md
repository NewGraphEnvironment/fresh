# Review: fresh#237 diff (p12), round 3

Verdict: **no bugs introduced by this diff.** One low-severity fragile finding. It predates the diff, but it is the same mechanism the round-2 NA fix targeted, and the fix only partly closes it. The optional fix is two lines.

## Mechanism

**The loader and the floor readers validate the same value against different rules.**

- **Loader** (`.frs_validate_rule`): validates a floor only when `!is.null(value)`. It then requires `is.numeric`, length 1 and (new in this diff) `!is.na`.
- **Readers** (`.frs_rule_ha_min`, then `.frs_rule_to_sql`, `build_wb_pred` and `.frs_run_connectivity`): treat `NULL` *or* `NA` as "no floor". The predicates then admit every polygon; connectivity falls back to 200 ha.

Every value the loader skips but a reader maps to "no floor" is a silent widening.

Round 2 aligned the two on one dimension, missingness (NA/NaN). This round lists every dimension a floor value can vary on (presence, type, length, missingness, magnitude), plus the other places where two lists or two checks must agree.

## Findings

- **[severity: fragile, low, pre-existing]** R/frs_params.R:257 and :275, with R/utils.R:387.
  A floor key that is present but has no value still loads and silently means "no floor".
  - **Inputs:** YAML `wetland_ha_min:` (empty), `wetland_ha_min: ~` and `wetland_ha_min: null` all parse to a key that is present but `NULL`. The same holds for `lake_ha_min`.
  - **Why the loader misses it:** its guard is `!is.null(rule[["…_ha_min"]])`, so it skips the whole check, including the wrong-type check.
  - **What the readers do:** `.frs_rule_ha_min()` returns `NULL`, so `rear`/`spawn` and the bucket get no `area_ha` clause, and connectivity uses 200.
  - **Verified:** I loaded all 12 combinations (L or W rule × floor key × empty / `~` / `null`). All 12 load, and `.frs_rule_to_sql()` emits an unfloored polygon subquery for each.
  - **Why it matters:** the new comment at :262 / :280 says the loader rejects a missing floor "rather than silently widen the polygon set". That holds for `.nan` / `.na.real` but not for an empty value, which is the more likely typo. The codebase already fixed this exact presence check for `mad` (:229-232: "Key presence, not !is.null(): an empty `mad:` parses to NULL and must error rather than silently mean 'no MAD filter'").
  - **Not a regression:** before the diff an empty floor also meant "no floor" in every reader.
  - **Optional fix:** change the two guards to key presence, `if ("lake_ha_min" %in% keys)` and `if ("wetland_ha_min" %in% keys)`. `is.numeric(NULL)` is FALSE, so the existing "non-missing numeric scalar" error then fires, and a value-less key of the wrong type hits the wrong-type error. A test would add `""` / `"~"` to the `cases` loop in test-frs_params.R:235.

## Where the mechanism reaches (each checked)

1. **Floor value, each dimension against the loader and `.frs_rule_ha_min`:**
   - **Absent key:** no floor. Intended.
   - **Present key, NULL value:** the **finding** above.
   - **Type:**
     - character, logical and list are rejected by `is.numeric`.
     - YAML `[10]` becomes `10L` (scalar) and is accepted correctly.
     - `[]` becomes `list()` and is rejected.
   - **Length:** 0 or more than 1 is rejected by the loader. If hand-built, the helper's `is.na(x) ||` errors (R 4.5: "'length = 2' in coercion to 'logical(1)'"), so it is loud.
   - **Missingness:** NA and NaN are now rejected (tested).
   - **Magnitude:**
     - `.inf` matches nothing (accepted by convention).
     - `-.inf` becomes `'-Infinity'::double precision` and matches everything, which is literally what the author wrote.
     - A negative floor behaves the same way. Neither is silent.
2. **Pairing of floor key and type.** Two lists must agree:
   - the loader's two hard-coded `if` blocks (lake_ha_min needs L, wetland_ha_min needs W)
   - the helper's `keys <- c(L = "lake_ha_min", W = "wetland_ha_min")`

   They agree today. Both sides are pinned: the loader by the existing wrong-type tests, the helper by test-utils.R `.frs_rule_ha_min` and test-frs_params.R "reads only the floor key of the rule's type". R has no floor on either side.
3. **`waterbody_type` grammar across consumers.** These read it differently:
   - the loader: character scalar in L/R/W
   - the helper: `is.character`, then `%in%` L/W
   - `.frs_rule_to_sql`: `%in%`
   - `.frs_find_waterbody_rule`: `identical`
   - the connectivity loop: `%in%`
   - `.frs_waterbody_tables`: `switch`

   They agree for every value the loader admits. They diverge only for hand-built factors or named vectors. For example, `factor("W")` makes `switch` warn and pick the *lake* tables, which is pre-existing; the helper now drops the floor for it. No loader path produces these values, so no finding.
4. **Polygon tables.** `build_wb_pred()` hard-codes `fwa_lakes_poly`, but the main `rear` predicate and connectivity use `.frs_waterbody_tables("L")`, which is lakes plus `fwa_manmade_waterbodies_poly`. This is known and was logged as out of scope in the #240 findings. The new comment "so the two can't disagree" is accurate for the floor only, not for the polygon set.
5. **Default when no floor is declared.** The predicates apply no floor; connectivity applies 200 ha. This predates the diff and is documented in the new comment at frs_habitat.R:1246.
6. **Paths that build rules without the loader:**
   - `frs_habitat(rules=)` goes through `frs_params()`, so it uses the loader.
   - `link` calls `frs_params()`, and `lnk_rules_build()` skips NA floors before writing YAML (`link/R/lnk_rules_build.R:282, 363, 377`).
   - Hand-built `params` / `sp_params` passed to `frs_habitat()` / `frs_habitat_classify()` / `frs_habitat_predicates()` still fail open on an NA floor through the helper. Round 2 accepted that by design, and the bucket path was already lenient before the diff.
7. **Same presence dimension outside the floor (pre-existing, out of scope, noted only).** An empty `waterbody_type:` loads and silently drops the waterbody constraint. Verified: `- waterbody_type:` plus `edge_types_explicit` compiles to a plain edge-type rule that inherits gradient. The same `!is.null()` gate covers `area_only`, `thresholds` and `edge_types_explicit`.

## Verified clean

- **Readers:** grep of `R/` for `ha_min` / `area_ha` finds no reader of the floor outside the three helper call sites. `.frs_connected_waterbody` receives the value as an argument, and `ranges$lake_ha` belongs to the CSV path.
- **Tests:** I ran the four changed test files.

  | File | Fail | Pass | Skip |
  |---|---|---|---|
  | test-frs_params | 0 | 172 | 2 |
  | test-utils | 0 | 59 | 0 |
  | test-frs_habitat_predicates | 0 | 111 | 0 |
  | test-frs_habitat | 0 | 56 | 0 |

  The NA/NaN loader test covers both keys and both NA spellings. `expect_gt(n_checked, 0L)` correctly omits `info`.
- **Checklist (R):**
  - `[[ ]]` is used throughout, so there is no `$` partial match.
  - `keys[[wt]]` on a named atomic is guarded by `%in%`.
  - yaml mixed-type lists are handled by `.frs_sql_num`'s `unlist`.
  - Inf and NA cannot reach `sprintf` as bare words: `.frs_sql_num` writes Inf as `'Infinity'::double precision`, and NA is now rejected by the loader.
  - `.frs_rule_ha_min` was inserted after `.frs_rules_to_sql`'s roxygen block and function, not between a roxygen block and its function, so no `@export` or `@noRd` is rebound.
