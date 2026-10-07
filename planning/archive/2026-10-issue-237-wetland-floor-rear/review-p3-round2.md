# Review: p3 (data-raw/rear_wetland_floor_check.R + logs + findings), round 2

## Findings

- **[bug]** planning/active/findings.md, the table under "Rearing still in sub-floor wetlands after the fix", column "persisted rearing" (NATR 355 (29.1), PARS 307 (22.4), BULK 20 (1.4)). The script's `small_wetland_persisted_*` and the edge CSV's `persisted_*` count **pre-fix** persisted rearing. That includes every segment the fix drops: all `old AND NOT new` segments are `small_wetland` by construction (checked: dropped = dropped ∩ small_wetland = 62 / 77 / 5, all on edge 1000 / 1100). So the column overstates "still … after the fix" by the `dropped_persisted_*` rows: 40 / 60 / 2.
  - Rearing that is actually still there (`persisted AND new AND small_wetland`, measured ad hoc): NATR **315 (27.0 km)**, PARS **247 (19.3 km)**, BULK **18 (1.3 km)**.
  - The script header (lines 18-24) has the same mislabel. It describes the block as "segments / km the new predicate still admits … for the new predicate and for persisted rearing".
  - Fix either way: retitle the column and header "persisted rearing before the fix", or add `persisted AND new` columns to the script and report those.
  - The "of which edge 1050 / 1150" column and the NEWS figure 307 (26.4 km) are unaffected, because the fix drops only 1000 / 1100 edges. PARS 244 (19.1) is a sum of rounded CSV values. It matches the exact 244 / 19.08 km.

- **[fragile]** planning/active/findings.md, both tables. The headers read "dropped by predicate (km)", "dropped from persisted rearing (km)", "new predicate (km)" and so on, but each cell is "segments (km)", e.g. "62 (3.0)". If someone quotes this to link, "62" reads as km. Use headers like "segments (km)".

- **[fragile]** NEWS draft, "For NATR BT, 307 segments (26.4 km) of persisted rearing sit on wetland-flow lines in wetlands under 1 ha." This is the pre-fix `fresh_default` count. It is not intersected with `new`, which doesn't matter because 1050 is always admitted. But after link reruns, `cluster_rearing` can drop 1050 lines that the removed 1000 segments used to connect, so 307 is an upper bound for the post-release state. The sentence is fine as an approximate figure. Don't pair it with "at least" language.

## Round 1 fixes: verified

- **`small_wetland` now matches the rule's own test.** It is `EXISTS key AND NOT EXISTS (key AND area_ha >= floor)`, the exact complement of the compiled `waterbody_key IN (SELECT … WHERE area_ha >= floor)`.
  - The correlation is correct: the inner alias `w` is scoped per subquery, and `s.waterbody_key` binds to the outer table.
  - A NULL `waterbody_key` (18k / 30k / 11k accessible rows) makes the first EXISTS false. So `small_wetland` is FALSE, never NULL.
  - `w_floor` is rendered through `.frs_sql_num()` in the same form the predicate uses (1 / 0.5).
- **`sprintf` argument order is right:** floor, pred_old, pred_new, hab_src, wsg_q map to the five `%s` in order. The predicates are passed as arguments, not as the format, so a `%` in them is harmless. `paste()` appends the outer SELECT without re-formatting.
- **Edge query.** `WHERE small_wetland AND (new OR persisted)` with per-column FILTERs is correct. Per-edge sums reconcile with the pooled columns: segment counts match exactly (596 = 9 + 587, 355 = 48 + 307, 381 = 3 + 377 + 1, 307 = 63 + 243 + 1, 35 = 0 + 35, 20 = 2 + 18), and km agree to within rounding.
- **The header now says waterbody keys.** `dropped_wetlands` is `count(DISTINCT waterbody_key)`, and dropped rows are all non-NULL-key W matches.
- **The NEWS lead uses persisted numbers with "at least".** I verified the lower bound holds against link's post-classify additions:
  - `frs_habitat_overlay` (user_habitat_classification) has no BT rows for NATR / PARS. Its BULK CO rows cover none of the 2 dropped segments.
  - `frs_order_child` is not active: there is no `channel_width_min_bypass` in `default` rules.
  - `rearing` has no NULLs among accessible rows.
- **The findings tables match the CSVs exactly:** 12,222→12,160, 62 (3.0), 40 (2.1), 49; 11,859→11,782, 77 (3.8), 60 (3.1), 64; 8,017→8,012, 5 (0.1), 2 (0.0), 5. The second table matches as well: 596 / 355 / 307, 381 / 307 / 244, 35 / 20 / 18.
- **The script reproduces.** A rerun of `Rscript data-raw/rear_wetland_floor_check.R NATR BT` gave byte-identical `natr_bt.csv` and `natr_bt_edge.csv`, and a `.txt` that differs only in the date line. The original logs were restored afterwards.
- **"`default*`" in NEWS is accurate.** `default_tuned` has no rules.yaml but `extends: default`. `default`, `default_extrabreaks` and `default_rearbreaks` all carry `wetland_ha_min` for BT, CH, CO, RB, ST and WCT, with no spawn-side W floors.
- **Checklist.** The script uses `pkgload::load_all` (source tree), has no top-level `on.exit`, and no `%||%`. The NA floor is excluded by the identical-predicate stop.
