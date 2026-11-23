# Findings — Backlog move 2: rules loading and persist validators (#319)

## Issue context

**If we do it:** a bad rules file or a mismatched target fails loudly instead of classifying wrongly. **If we never do:** rules silently empty under the C locale, reservoirs stay out of the lake bucket, and a 200 ha floor applies that no rule states.

This is move 2 of `planning/backlog.md` (#315). Run `/planning-init <this issue>`: its batches are the scope, one phase per batch, one PR.

When the plan finds that a batch, or one of its members, is more than one PR's work, it carries the first piece and files each other piece as its own issue naming move 2, and leaves it out of `planning/backlog.md`: the next `/backlog-sweep` reads an issue the file does not name as unplaced, and folds it into a move other than this one.

## Batch 3: Rules loading and persist validators

**Why here:** Three of these fail silently: a non-ASCII byte under the C locale empties the rules (#267), reservoirs are left out of the lake bucket (#250), and a hidden 200 ha floor applies (#251). They share the rules loader and the persist-path validators.

**Touches:** `R/frs_params.R`, `R/frs_habitat_predicates.R`, `R/frs_col_join.R`, `R/frs_feature_find.R`, `R/utils.R`, `R/frs_habitat.R`, `R/frs_habitat_classify.R`, `CLAUDE.md`

**To decide at the gate:**

- #251: no floor, or refuse at rules load.
- #222: a target missing a flag column is altered, or refused.

| issue | title |
|---|---|
| #267 | Rules YAML read depends on the session locale; a non-ASCII byte empties the rules |
| #222 | Align other persisted-table appends and rule validators with #114 fixes |
| #239 | frs_col_join() types a subquery's columns text |
| #251 | waterbody-connected spawning falls back to a silent 200 ha floor when the L rule has none |
| #250 | lake_rearing bucket ignores reservoirs, while the L rule's rearing predicate includes them |





## Member issues

### #267 Rules YAML read depends on the session locale; a non-ASCII byte empties the rules

**If we do it:** the bundled habitat rules load the same way in every locale. **If we never do:** a session in the C/POSIX locale gets an empty rule set from `parameters_habitat_rules.yaml`, and many tests fail with no error that names the cause.

## Problem

`.frs_load_rules()` reads the rules with `yaml::read_yaml(path)`. `read_yaml()` opens the file with `encoding = "UTF-8"`, so R re-encodes its contents to the session's native encoding as it reads. The bundled `inst/extdata/parameters_habitat_rules.yaml` contains a non-ASCII character (an em-dash in a comment). Under `LC_CTYPE=C` that character cannot be converted: `readLines()` warns `invalid input found on input connection` and stops there, keeping only the lines before it. In the bundled file the em-dash is on line 5, after four comment lines, so `read_yaml()` returns `NULL`, and the `length(raw) == 0` branch returns `list()`, so every species gets no rules. Further down a file the same character truncates it silently instead: `a: 1`, `b: 2`, a comment with an em-dash, then `c: 3` reads as `list(a = 1, b = 2)`.

Reading the bundled file on `main` (0.42.0) under `LC_ALL=C`:

| Read | Top-level entries |
|---|---|
| `yaml::read_yaml(path)` | 0, with the warning above |
| `yaml::yaml.load(readLines(path, encoding = "UTF-8", warn = FALSE))` | 11 |
| `yaml::read_yaml(path)` in a UTF-8 locale | 11 |

In a container with no locale set, `testthat::test_local()` on 0.42.0 gave 133 failures from this. Under `LANG=C.UTF-8` the same run gave 0.

## Proposed Solution

Read the bytes without re-encoding: `yaml::yaml.load(readLines(path, encoding = "UTF-8", warn = FALSE))`. `readLines(encoding =)` marks the strings as UTF-8 rather than converting them. A guard on an empty result would catch the bundled file's case but not truncation, so the read change is the fix.



### #222 Align other persisted-table appends and rule validators with #114 fixes

If we do it: every long-lived table append and every rules YAML range field gets the same guards as `to_streams` / `mad` in #114, so a schema or config drift errors before any data is deleted. If we never do: each of these fails silently or destructively the next time a column or config shape changes.

Found by code-check round 3 on #221 (see `planning/archive/2026-09-issue-114-mad-predicate/review-round3.md`). These were already there before #114:
- **`to_habitat` persist** (`R/frs_habitat_classify.R`). A table persisted before `wetland_rearing` existed fails the INSERT *after* the per-WSG DELETE. Reuse `.frs_persist_columns()`.
- **`frs_feature_find(append = TRUE)`.** A target created without `feature_id` makes a later append with `col_id` fail.
- **`frs_col_join()` type lookup.** It falls back to `text` silently, and with a same-named table in two schemas on `search_path`, the last one wins.
- **Rules YAML `gradient` / `channel_width`.** Neither checks `is.finite` or `min <= max`, so a reversed range silently matches nothing. Mixed int/float lists come back as a list; see the `mad` validator in `.frs_validate_rule()`.
- **Every rule field treats an empty value (`key:`) as absent.** `mad` now errors on this.

### #239 frs_col_join() types a subquery's columns text

**If done:** a caller can join columns from a subquery with `frs_col_join()` and get the source types. **If never:** every such caller has to `ADD COLUMN` with the right type itself. One that does not gets `text` columns, and the first numeric predicate on them (`s.mad_m3s BETWEEN ...`) fails with no operator.

`R/frs_col_join.R:85-87` sets `col_types <- rep("text", ...)` and looks up real types only when `from` is a table name. `:113-115` then runs `ADD COLUMN IF NOT EXISTS <col> text`. The `UPDATE` assignment-casts doubles to text without complaint, so nothing fails until the column is read numerically.

Found in NewGraphEnvironment/link#305, where `.lnk_discharge_join()` now adds `mad_m3s double precision` itself rather than relying on `frs_col_join()` (link@312e195).

A fix: resolve a subquery's column types with `SELECT * FROM (<from>) s LIMIT 0` and the result's attribute types, or accept a `col_types` argument.


### #251 waterbody-connected spawning falls back to a silent 200 ha floor when the L rule has none

**If done:** a species whose spawning requires connected rearing uses its rear L / W rule's floor, or none if the rule declares none. **If never:** an L rule with no `lake_ha_min` still has a 200 ha floor on the spawning side. Nothing in the rules says so.

## Problem (fresh@e247ca1, v0.39.0)

`.frs_run_connectivity()` sets `wb_ha_min <- 200` and overrides it only when the first rear L / W rule carries a floor (`R/frs_habitat.R:1248-1262`). A rules file that sets no `lake_ha_min` reads as "any lake". On the spawning side it means "200 ha or more".

Today every bundle that uses this path (SK, KO) sets 200 ha explicitly, so nothing moves. The default is a trap for the next species.

## Proposal

No floor when the rule declares none, matching the rearing predicate. Or refuse at rules load: require a floor on the first rear L / W rule of a species whose spawn rules carry `requires_connected: rearing`.

Relates to link#310.


### #250 lake_rearing bucket ignores reservoirs, while the L rule's rearing predicate includes them

**If done:** a species' `lake_rearing` bucket reads lakes and reservoirs, as its `rearing` predicate already does. **If never:**
- A reservoir line can be `rearing` through the L rule and never `lake_rearing`.
- Lake hectares rolled up from the bucket leave reservoirs out.

## Problem (fresh@e247ca1, v0.39.0)

- `.frs_rule_to_sql()` builds an L rule's polygon test from `.frs_waterbody_tables("L")`, which is `fwa_lakes_poly` and `fwa_manmade_waterbodies_poly` (`R/utils.R:179-185`, used from `:286`).
- The bucket predicate in `.frs_habitat_predicates()` hard-codes `fwa_lakes_poly` (`R/frs_habitat_predicates.R:205-211`).
- The spawning-connectivity pass reads both tables (`R/frs_habitat.R:1266`).

So the two predicates read from one rule disagree on reservoirs. The 368 manmade waterbodies carry about 245 km of lines province-wide (`fwa_stream_networks_sp` × `fwa_waterbodies`, `waterbody_type = 'X'`, 2026-10-07).

## Proposal

`build_wb_pred()` takes its tables from `.frs_waterbody_tables()` for both L and W, with the area floor applied to each, as `.frs_rule_to_sql()` does.

Relates to link#310 (decision 5: reservoirs count as lakes, in fresh's bucket and in link's rollup).


## Errors Encountered

| Error | Resolution |
|-------|------------|

## Measurements (2026-11-23)

### Branch tests against main's code
The branch's six touched test files, copied into a worktree of `origin/main` (f3e331d) and run against main's R code: every new test is red there (C-locale x2, range/empty-key x5, bucket tables x3, #251 x2, col_join live x3 plus the mocks that name the new helper, flag migration x2, feature_id append x1). All green on the branch.

### Direct #250 check, CHWK, CO + BT, bundled rules
`frs_habitat()` with fresh main and with the branch, each from its own library, same segmentation (10,752 segments, 0 differing). `accessible`, `spawning`, `rearing`, `wetland_rearing`: 0 differences. `lake_rearing`: BT 162 -> 182 (+20 rows on 2 reservoirs), CO 184 -> 208 (+24 rows on 4 reservoirs); every difference FALSE -> TRUE on a `waterbody_key` in `fwa_manmade_waterbodies_poly`. Script: scratchpad `lake250.R` (ad hoc measurement, nothing cached).

### Functions link reaches
85 fresh functions are reachable from link's 14 exports and 4 `getFromNamespace` internals (codetools call graph on the installed branch). 12 functions changed or are new; 11 of them are reachable:
- `.frs_load_rules`, `.frs_validate_rule`, `.frs_validate_rule_range`: refuse only shapes none of link's 24 rules files carry (measured, and by the plan review).
- `.frs_run_connectivity`, `.frs_connected_waterbody`: byte-identical SQL for a declared floor; every link bundle declares 200 for SK/KO.
- `frs_col_join`, `.frs_query_col_types`: the same types for link's two calls (`double precision`, `text`, `integer`, measured both ways).
- `.frs_habitat_target`, `.frs_col_types_of`: add a flag only where it is missing.
- `.frs_near_river_check`: message text only.
- `frs_habitat_predicates`: `lake_rear` includes reservoirs (deliberate, #250).

### link's suite, fresh main vs branch
link origin/main (be06e2b4) worktree, `devtools::test()` with `R_LIBS` naming a library holding fresh main (f3e331d) or the branch (21db9a1), each confirmed by `find.package()` and by whether `.frs_query_col_types` exists. 1,492 tests on each side; every test's expectation count, failures, errors and skips identical (0 rows differ). Both sides: 2 failures + 3 errors in 4 tests (`lnk_habitat_validate` near_river persisted distances, `lnk_pipeline_prepare` study_area_run.sh #349, two `lnk_wsg_resolve` closure tests): link's own, identical with fresh main. As the plan review predicted, no link test reads fresh's `lake_rearing` from a database, so the #250 change shows only in the direct CHWK check above.

### code-check enumeration (ends the review loop)
Round 4 found a defect inside round 3's fix (doc text claiming a table source keeps its types, false for char(n)/bit(n)), so the loop ends on enumeration, two sets:
1. **Mechanism "a modifier-less type name is at least as wide as the source type"** — every `pg_type` with `typmodin <> 0` on the live fwapg, 24 types (round 4, `review-round4.md`): only bpchar, bit and their arrays are narrower bare; all four mapped by the CASE. varchar, varbit, time, timestamp, timestamptz, timetz, interval, numeric (+arrays) are unconstrained or maximal bare; geometry/geography (+arrays) take any subtype and SRID. Domains arrive as their base type. Sweep through `frs_col_join()` of every type with a modifier set: all created at typmod -1, values equal.
2. **Every claim in the tree about how `frs_col_join()` types columns** (`git grep` over R, man, NEWS, CLAUDE.md, README, vignettes, tests, data-raw), 6 sentences: NEWS.md:17, CLAUDE.md:336, `@param cols` (and `man/frs_col_join.Rd`), `.frs_query_col_types()` roxygen, `R/frs_near_river.R:351` comment, `R/frs_barriers_minimal.R:96` ("Use frs_col_join() to add ltree columns", true from this branch). After the round-4 rewording, each matches the code.
