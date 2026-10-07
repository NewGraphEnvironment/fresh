# Review: fresh#237 diff (p12), round 2

Verdict: **one low-severity fragile finding. No bugs.** Mergeable as is. The fix for the finding is optional and one line.

## Findings

- **[severity: fragile, low]** R/utils.R:387 (`.frs_rule_ha_min`) with R/frs_params.R:265 and :281 (loader).
  An `NA`/`NaN` floor now fails open and silently means "no floor". The loader checks a floor only for `is.numeric() && length == 1`, so YAML `wetland_ha_min: .nan` or `lake_ha_min: .na.real` loads (verified: they parse to `NaN` / `NA_real_` and `.frs_load_rules()` accepts them).
  - **Before:** the main `rear`/`spawn` path wrote `area_ha >= NaN` (or `NA`) into SQL. Postgres reads that bare word as a column and errors, so the bad config surfaced. The connectivity pass did the same through `.frs_sql_num(NA)`.
  - **Now:** `.frs_rule_ha_min()` returns `NULL`. The main predicate admits every polygon of that type, and `.frs_run_connectivity()` quietly substitutes 200 ha.
  - **Why it matters:** the bucket predicate already dropped NA silently, so this unifies on the lenient side. It is reachable only through a malformed YAML or an in-memory rule, but it turns a loud config error into a silent widening of `rearing`. That is the "guard that fails toward pass" pattern.
  - **Optional fix:** have the loader reject non-finite-or-NA floors. Add `|| is.na(rule[["lake_ha_min"]])` (and the same for `wetland_ha_min`), matching how `mad` already uses `is.finite`. This keeps the helper's NULL-on-NA contract harmless.

## Verified clean (no action)

- **L and R rules give byte-identical SQL.** I compared old and new `.frs_rule_to_sql()` (sourced from `HEAD`) on these rules. All were `identical()`:
  - L with no floor
  - L with floor 200, 0.5, `Inf`, `10L`, and `list(10L)` (yaml mixed-type)
  - L with `edge_types_explicit`
  - R with no floor, and R with `channel_width`
  - W with no floor
  - a stream rule

  The only output that changed is W + `wetland_ha_min`, as intended.
- **Bundled params, 11 species x {cw, mad} x 4 predicates (88 compared).** Only `rear` differs, and only for the species with a floored W rule (BT, CH, CO, RB, ST, WCT). Each difference is exactly the added `WHERE area_ha >= <floor>` on the wetlands subquery; the rest of the string is identical. `spawn`, `lake_rear` and `wetland_rear` are unchanged for every species.
- **`build_wb_pred()`.** The rule passed in always comes from `.frs_find_waterbody_rule(…, "L"/"W")`, which uses `identical(wt, code)`. So `.frs_rule_ha_min()` reads the same key the old `ha_key` argument named, and the output is unchanged.
- **Connectivity floor (`frs_habitat.R` ~L1253).** None of the bundled species change: SK and KO, the only ones with spawn `requires_connected`, have L-only rear rules. W-first species now get their `wetland_ha_min` instead of 200, as intended. A W rule with no floor still gets 200 here while the rear predicate applies none. That mismatch predates this diff and is documented in the new comment.
- **Odd `waterbody_type` values.** These all return NULL and do not error: `c("L","W")`, `factor("L")`, `NA_character_`, a missing key, and a NULL rule. In `.frs_rule_to_sql()`, a length-2 type still errors earlier, in `.frs_waterbody_tables()`'s `switch` and the pre-existing `%in%` inside `if`, as before. A non-scalar floor (`c(1,2)`, `numeric(0)`) errors in `is.na() ||`. The old code also errored on these, and the loader rejects them.
- **`.frs_sql_num`** handles every floor type the loader admits (integer, double, `Inf`, and yaml-list via `unlist`).
- **Bypassing the loader.** Every `link` caller of `frs_habitat_predicates()` builds `sp_params` from `fresh::frs_params()`, so the loader's type/key pairing holds. `link`'s `lnk_rules_build()` puts `wetland_ha_min` only on W rules and `lake_ha_min` only on L rules. Dropping a cross-type floor key therefore affects only hand-built rules that the loader would reject anyway (by design, and tested).
- **Other floor readers.** I grepped `R/`. All three readers go through the helper:
  - `.frs_rule_to_sql`
  - `build_wb_pred`
  - `.frs_run_connectivity`

  `frs_params.R:563` (`<prefix>_lake_ha_min` CSV column, which becomes `ranges$lake_ha`) is CSV-path and unrelated. `frs_lake_fetch` / `frs_wetland_fetch` `area_ha_min` are separate arguments.
- **Tests can reach the failure mode.** Each new assertion fails against the old code:
  - The connectivity test expects 1.5; the old code gave 200.
  - The rear predicate test has `expect_false(grepl("fwa_wetlands_poly\\)"))`.
  - The exact-SQL `wetland_ha_min` test.

  The bundled-rules loop guards against a vacuous pass with `expect_gt(n_checked, 0L)`, and it passes no `info` to `expect_gt`.
