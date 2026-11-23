# Plan review — #319 (Plan agent, 2026-11-23, background, delivered mid-Phase 5)

Written by the parent session from the agent's reply (the Plan type cannot write). Verdicts after probing are in the last column of each item.

## Blocker
None. Verified: all 24 rules files on link origin/main (the plan said 10; the other 15 are `data-raw/logs/wetland_door_364/score/bundles/*/rules.yaml`) plus fresh's carry no null rule/spawn_connected value and no list/reversed/non-finite range; `lnk_rules_build()` never writes a NULL; SK/KO are the only `requires_connected` species and every first L rule sets 200.

## Gap
1. Phase 4 plan says temp table; code uses `dbColumnInfo()$.oid` + `format_type()`. Fix the plan text; unit tests must mock `.frs_query_col_types`. — **Already done** in b973c46 (plan note, mocks, CLAUDE.md).
2. Text #239 makes stale: `R/frs_near_river.R:350-357` (comment + error message "frs_col_join() types a joined column text"), test comment `test-frs_habitat_classify.R:486`, link `R/lnk_discharge.R:317` (owed issue). — **Accepted.**
3. Phase 3 pinned tests (already updated) and roxygen `R/frs_habitat.R:1647` ("fwa_lakes_poly with area_ha >= lake_ha_min"). — **Accepted** for the roxygen.
4. Phase 5 turns `test-frs_habitat_classify.R:518-570` red: it mocks `.frs_cols_of` and stubs `DBI::dbGetQuery` only inside `frs_habitat_classify`; the new type read in utils.R hits the mock conn. Fix: one mockable column-type helper beside `.frs_cols_of`; refuse a wrong type before any ALTER; keep flags out of `cols_added`. — **To probe, then accept.**
5. `frs_feature_find`: `ADD COLUMN IF NOT EXISTS feature_id text` does not refuse an existing non-text `feature_id` (decision 2 says refuse). — **Accepted.**
6. Phase 1 lost the file name in YAML parse errors (`read_yaml()` passed `error.label = file`). — **To probe, then accept.**
7. NEWS must name every user-visible change (empty keys now refused, mixed ranges accepted, #251 no floor, `frs_col_join()` types and missing-column error), not only #250. — **Accepted** (Phase 6).

## Scope
1. Empty-value check covers top-level rule keys only: `channel_width_min_bypass` sub-keys and `spawn_connected` optional keys still read empty as absent. link documents `edge_types: null` in spawn_connected as "no filter" (lnk_rules_build.R:642). — **Decision (parent, mechanism):** extend to bypass sub-keys (a rule field; nothing emits null there); leave `spawn_connected` out (a block, not a rule field, where null has a documented meaning) and say so in NEWS.
2. Owed link issue gains: link's own #267 (`names(yaml::read_yaml(rules_path))`, lnk_config.R:126), stale roxygen lnk_rollup_wsg.R:296-300, lnk_discharge.R:317. — **Accepted.**
3. Legacy exported `frs_habitat_species()` stays lakes-only and now disagrees with `frs_habitat_classify()`: file as its own issue naming move 2. — **Accepted.**

## Assumption
1. Rules-file count 24, not 10; conclusions hold. — corrected.
2. Other #250 effects checked: `.frs_bucket_connected` keys on `waterbody_key` only; `.frs_connected_waterbody` reads `rearing`; near_river already includes manmade; link's overlay uses spawning/rearing only; `lnk_habitat_validate`'s `rear OR lake_rear OR wetland_rear` moves only for an `area_only` L rule (link has none); link's ha rollups already join manmade. Net: only `lake_rearing` should move.
3. link's two `frs_col_join` calls are typmod-free table sources: unchanged.

## Ordering
1. SK/KO "before" counts must come from a build without Phase 3. — Superseded: replaced by SQL byte-identity (progress.md).
2. Revise Phase 4 plan text before docs. — Done.

## Acceptance
1. #251 "SK/KO counts equal" cannot fail (both declare 200): a non-regression check only; the proof is the mock + SQL test. — **Agreed**; worded so in progress.md.
2. #250 "link suite shows only reservoir moves" will show zero differences (no link test reads fresh's `lake_rearing` from a DB). Add a direct check: classify one WSG with reservoirs on main and on the branch; `accessible`/`spawning`/`rearing`/`wetland_rearing` identical, every `lake_rearing` difference FALSE→TRUE on a manmade `waterbody_key`. — **Accepted** (Phase 6).
3. Phase 4 "unqualified source" test passes on main unless two same-named tables differ in type. — **To probe**: the test's source is a pg_temp table, which main's `information_schema` filter on `current_setting('search_path')` cannot see, so main types it text; to be confirmed by running it against main.
