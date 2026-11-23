# Task: Backlog move 2: rules loading and persist validators (#319)

**If we do it:** a bad rules file or a mismatched target fails loudly instead of classifying wrongly. **If we never do:** rules silently empty under the C locale, reservoirs stay out of the lake bucket, and a 200 ha floor applies that no rule states.

Members: #267, #222, #239, #251, #250. Plan approved by the owner 2026-11-22.

## Context

Move 2 of `planning/backlog.md` (#315). It is one batch of five issues that share the rules loader and the persist-path validators. Three of them go wrong silently:

- a non-ASCII byte under the C locale empties the rules (#267);
- reservoirs are left out of the `lake_rearing` bucket (#250);
- a 200 ha floor applies to waterbody-connected spawning without any rule stating it (#251).

The other two (#222, #239) are config or schema drift that should fail loudly before anything is written.

The goal is one PR on branch `319-backlog-move-2-rules-loading-and-persist`, cut from `origin/main` at `f3e331d` (v0.56.0). The issue has no comments.

## What exploration found

- **#267:** `.frs_load_rules()` (`R/frs_params.R:157`) is the only YAML read in `R/`. Every rules file link ships, and fresh's own bundled file, has one non-ASCII line (the em-dash in the "DO NOT EDIT" header comment), so this is live for every bundle.
- **#251:** the fallback lives in `.frs_run_connectivity()` (`R/frs_habitat.R:1292-1303`, `wb_ha_min <- 200`). It reaches SQL through `.frs_connected_waterbody(waterbody_ha_min = 200)` (`:1821`, used at `:1911-1915`). **link calls `.frs_run_connectivity` directly** through `getFromNamespace` (`lnk_pipeline_connect.R:101`).
  - I parsed the rules files link carries (24 on origin/main, per the Plan review: 4 configs, its bundled copy, 4 test fixtures, 15 `data-raw` score bundles) plus fresh's bundled file. Every species whose spawning has `requires_connected: rearing` (SK, KO) sets `lake_ha_min: 200` on its first rear L rule.
  - So either answer to this issue leaves link's outputs unchanged.
- **#250:** `build_wb_pred()` (`R/frs_habitat_predicates.R:286-303`) hard-codes `fwa_lakes_poly` and `fwa_wetlands_poly`, while `.frs_waterbody_tables()` (`R/utils.R:287`) gives L as lakes plus manmade waterbodies.
  - **This changes link's outputs on purpose:** reservoir lines become `lake_rearing`. That is the owner's decision 5 on link#310 ("reservoirs count as lakes, in fresh's bucket and in link's rollup"). link's rollup already counts reservoir hectares, and link#310's Outcome names fresh#250 as the missing half.
  - The legacy wide path in `frs_habitat_species()` (`R/frs_habitat.R:1203`) also hard-codes lakes. It is not rule-driven and not in this issue's scope, so it is left as is.
- **#222 (rules):** the `gradient` and `channel_width` checks (`R/frs_params.R:435-444`) test only "numeric, length 2". There is no check for finite values or `min <= max`.
  - A mixed int/float list (`[0, 0.05]`) comes back from yaml as a list and is refused today. `mad` already normalises that shape (`:191-195`, `:265-278`).
  - Only `mad`, `lake_ha_min`, `wetland_ha_min` and `near_river` refuse an empty `key:`. Every other key reads an empty value as absent.
  - None of link's rules files has an empty key or a bad range, so the stricter checks refuse nothing link ships.
- **#222 (persist):**
  - `.frs_habitat_target()` (`R/utils.R:94-133`) runs `CREATE TABLE IF NOT EXISTS` with the flag columns, but adds only `linear_feature_id` to an older target. A target created before `wetland_rearing` existed fails the INSERT. Since #293 the DELETE and INSERT share one transaction, so the failure rolls back rather than losing rows, but the error never names the cause.
  - `.frs_feature_find_write()` (`R/frs_feature_find.R:248-270`) appends `feature_id` into a target that may not have that column.
- **#239 and #222 (col_join):** `frs_col_join()` (`R/frs_col_join.R:85-116`) types a subquery's columns as `text`.
  - For a table it reads `information_schema.data_type`, which says `USER-DEFINED` for ltree or geometry, so the `ALTER` fails. It also falls back to `text` when it finds no match.
  - With no schema given, it matches every schema on `search_path`, and the last match wins.
  - link's two calls (`lnk_pipeline_prepare.R:889,903`: `channel_width`, `channel_width_source`, `stream_order_parent`) read the same types under `format_type()` as under `data_type` (local fwapg, measured today: `double precision`, `text`, `integer`). So changing how types are resolved leaves link's tables unchanged.

## Decided at the gate (owner, plan approval 2026-11-22)

1. **#251: no floor when the rule declares none** (recommended).
   - This matches the rearing predicate and `.frs_rule_ha_min()`. It also matches link's existing meaning of a blank floor as "any size" (CO, link#310 decision 2).
   - Refusing at load would add a requirement that only this one path has.
   - Output-neutral for every shipped bundle (above).
2. **#222: a target missing a column we write is altered, not refused** (recommended).
   - This matches `to_streams` (`.frs_persist_columns()`) and the `linear_feature_id` migration already in `.frs_habitat_target()`.
   - Rows written before the column existed read NULL, meaning "never classified".
   - A column that exists with the wrong type is still refused.
   - The same answer applies to `frs_feature_find(append = TRUE)` and `feature_id`.
3. **#250 changes link's outputs, by link#310 decision 5.** link takes the change when it bumps its fresh pin. The link suite comparison below reports exactly which tests move, and every move must trace to reservoir lines entering `lake_rearing`.

## Phase 1: Locale-safe rules read (#267)

- [x] Test (`test-frs_params.R`): under `Sys.setlocale("LC_CTYPE", "C")`, restored with `on.exit`, cover two files:
  - the bundled rules file loads all 11 species;
  - a temp YAML with an em-dash comment between keys keeps the keys after it (the truncation case).
  - Confirm both fail on `main` first.
- [x] `.frs_load_rules()`: `yaml::yaml.load(readLines(path, encoding = "UTF-8", warn = FALSE))`, with a comment naming #267.

## Phase 2: Range and empty-value validators (#222, rules)

- [x] Tests for `gradient` and `channel_width`:
  - refuse a reversed range, `Inf`, `.nan`, length ≠ 2, a non-numeric element and a nested list;
  - accept a mixed int/float list `[0, 0.05]` and store it as a plain numeric vector, as `mad` is.
- [x] Test: an empty value (`key:`) on each other rule key is refused and the error names the key. This covers `edge_types`, `edge_types_explicit`, `waterbody_type`, `in_waterbody`, `area_only`, `thresholds`, `gradient`, `channel_width`, `channel_width_min_bypass`, `requires_connected` and `connected_distance_max`.
- [x] `.frs_validate_rule()`: one shared range check for `mad`, `gradient` and `channel_width`, run per element as the `mad` check does (finite, `min <= max`), plus a generic empty-key check.
  - The existing messages for `mad`, area floors and `near_river` stay as they are, since tests pin them.
- [x] `.frs_load_rules()`: normalise `gradient` and `channel_width` to numeric vectors beside `mad`.

## Phase 3: Waterbody floors and tables (#251, #250)

- [x] Test (pure R, `test-frs_habitat_predicates.R`):
  - the L bucket predicate reads `fwa_lakes_poly` and `fwa_manmade_waterbodies_poly`, each with the floor;
  - with no floor, neither table carries an area clause;
  - the W predicate is unchanged.
- [x] `build_wb_pred()` takes its tables from `.frs_waterbody_tables(type)` for L and W, and applies the floor to each (`UNION ALL` of `waterbody_key`), as `.frs_rule_to_sql()` does.
- [x] Test, #251: an L rule with no `lake_ha_min` gives `.frs_connected_waterbody()` no floor, and its lake-adjacent `EXISTS` carries no `area_ha` clause.
  - Check this through a mock of `.frs_connected_waterbody` called from `.frs_run_connectivity()`, plus the SQL text.
  - Also check that a declared 200 still passes 200.
- [x] `.frs_run_connectivity()`: `wb_ha_min <- NULL` unless the rule declares a floor.
  - `.frs_connected_waterbody(waterbody_ha_min = NULL)` drops the `lp.area_ha >= ...` clause when it is NULL.
  - Update the roxygen and comments.
- [x] Live check: on one group with SK, the SK and KO spawning counts on the bundled rules are unchanged before and after the change.

## Phase 4: Typed `frs_col_join()` (#239, #222 col_join)

- [x] Live tests (`test-frs_col_join.R`, using `frs_test_tbl()` names or `pg_temp`):
  - a subquery joining `double precision` and `integer` columns creates those types;
  - a table source with an ltree column works;
  - an unqualified source resolves through `search_path` to the same relation the UPDATE reads;
  - a column the source lacks errors before any `ALTER`.
- [x] *(Mechanism corrected during the build: no temp table. `.frs_query_col_types()` prepares `SELECT <cols> FROM <from> _src LIMIT 0` and reads the result's type OIDs through `DBI::dbColumnInfo()` and `format_type()`: no DDL, no temp-table privilege, one statement through any pooler. It loses the typmod, exactly as the `information_schema` lookup did, so link's columns keep their types.)* Resolve types once for both tables and subqueries: `CREATE TEMP TABLE pg_temp.<unique> AS SELECT <cols> FROM <from> _src LIMIT 0`, then read `format_type()` from `pg_attribute`, then drop the temp table.
  - The temp table resolves names exactly as the UPDATE does.
  - Remove the `text` fallback and the `information_schema` lookup.
  - Document that the call needs one backend and permission to create temp tables, as `frs_point_snap()` does.
- [x] Update the roxygen and the `CLAUDE.md` technical note "`frs_col_join()` subquery sources". The no-alias rule stays.

## Phase 5: Persist appends (#222, persist)

- [x] Live test: a `to_habitat` created without `wetland_rearing`, plus one other flag column, is altered.
  - The classify run succeeds.
  - Older rows read NULL in the added columns.
  - A flag column of the wrong type is refused before the DELETE.
- [x] `.frs_habitat_target()` adds any missing flag column (`accessible`, `spawning`, `rearing`, `lake_rearing`, `wetland_rearing`) as `boolean`, and refuses a non-boolean one. The column list is one `cols_` vector shared with the `CREATE`.
- [x] Live test: a `frs_feature_find(append = TRUE, col_id = ...)` into a target created without `feature_id` succeeds and adds the column.
- [x] `.frs_feature_find_write()`: when appending with an id, run `ADD COLUMN IF NOT EXISTS feature_id text`.

## Review corrections (Plan review, `review-plan.md`, folded 2026-11-23)

- [x] `.frs_load_rules()` passes `error.label = path`, which `read_yaml()` did (Gap 6).
- [x] Stale #239 text: `R/frs_near_river.R` comment and error message, a test comment, and the `R/frs_habitat.R` roxygen on lake polygons (Gaps 2, 3).
- [x] Flag-column types read through a mockable `.frs_col_types_of()`; the mocked classify test stubs it (Gap 4). `frs_feature_find()` refuses a non-text `feature_id` (Gap 5).
- [x] Empty `channel_width_min_bypass` sub-keys refused (Scope 1). `spawn_connected` stays out: it is a block, not a rule field, and link documents `edge_types: null` there as "no filter".
- [x] File the legacy `frs_habitat_species()` lakes-only path as its own issue naming move 2 (Scope 3): #330.

## Phase 6: link check, docs, release

- [x] Diff every fresh function link reaches: its exports (`lnk_preflight_fresh()`), its four `getFromNamespace` internals, and what those call. Record which of them this branch changes.
- [x] Run link's test suite against fresh `main` and against this branch, each from its own temporary library, and compare test by test (the method in #318's archive README).
  - Any difference must trace to #250's reservoir lines and nothing else.
- [x] Direct #250 check (review Acceptance 2): classify one group with reservoirs on `main` and on the branch; `accessible`, `spawning`, `rearing` and `wetland_rearing` identical, every `lake_rearing` difference FALSE to TRUE on a manmade `waterbody_key`.
- [x] `devtools::document()`, `lintr` per-file diff against `main`, and `pkgdown::check_pkgdown()`.
- [ ] Update `NEWS.md` and bump `DESCRIPTION` to 0.57.0 as the final commit. NEWS names the deliberate `lake_rearing` change, and that link takes it at its pin bump.

## Owed at the end (reported, done after merge)

- [ ] File a link issue covering two things:
  - `.lnk_discharge_join()` can drop its own `ADD COLUMN mad_m3s double precision` workaround once link pins ≥ 0.57.0 (#239);
  - the pin bump moves `lake_rearing` to include reservoirs (#250). Re-run `data-raw/pretest_run.sh` at that bump;
  - link's own #267: `names(yaml::read_yaml(rules_path))` in `lnk_config.R` reads nothing under the C locale;
  - stale text: `lnk_rollup_wsg.R` roxygen ("until that changes no reservoir is flagged") and `lnk_discharge.R`'s note on `frs_col_join()` typing text.

## Validation

- [ ] Tests pass
- [x] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved:

- **#267:** C-locale tests that are red on `main` and green on the branch.
- **Validators:** each refused shape has a test.
- **Effective guards:** restore each bug and watch its test go red.
- **#251:** the SK and KO before/after counts are equal.
- **#250:** the SQL-text test, plus link's suite showing only reservoir-driven moves.
- **#239:** live type assertions.
- **Persist:** live alter and refuse tests.
- **Full suite:** `devtools::test()` against the local Docker fwapg.

