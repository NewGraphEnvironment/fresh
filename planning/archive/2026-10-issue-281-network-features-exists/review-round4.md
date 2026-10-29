# Code-check round 4: #281 (branch at b37a8d5)

## Checklist read

- `code-check-infra.md`: in full (38,115 bytes).
- `code-check.md`: the prose of all 14 H3s under `## Mechanisms`, without the `|` table rows. Also read in full: "An assertion that matches an interpolated value cannot see the claim around it" and "Documentation Staleness". The other 22 headings outside Mechanisms were not read (machine config, URLs, YAML, security, spreadsheets/PDF: nothing in this diff).
- `code-check-r.md`: 26 of 111 headings read in full. They are the `data-raw/` source-tree rule, lintr against the installed package, regenerated binaries, tests that silently do not run, testthat `error` vs `failed`, `skip_if_not()` scope, `expect_gt()` and `info`, `$` partial matching, DB driver values, `::text` spelling, `paste()` with a zero-length argument, `identical()` on reader results, `R CMD check` against the installed package, `match()` on NA, `expect_false(identical())`, testthat `tolerance`, `data.frame()` recycling, `\<` / `\>`, failure snapshots, Postgres row order, `sprintf("%g")` in SQL, `information_schema`, editing an Rscript mid-run, undeclared `pkg::` in tests, `Rscript -e --args`, and `function(...)` mocks. 85 not read.
- `code-check-shell.md`: 1 of 67 read, "A verification command can be shadowed by a shell function or alias" (`diff` is shadowed here, so I used `/usr/bin/diff`). The diff has no shell. 66 not read.
- `code-check-spatial.md`: 2 of 93 read, "A GDAL failure partway through `sf::st_read()`" (`frs_db_query()` is `st_read()`, but it goes through DBI, not GDAL, so the rule does not apply) and "FWA `upstream_route_measure`". 91 not read.

## Findings

- **[severity: prose]** `data-raw/logs/network_features_exists_281/README.md:56`: the SALR ST `fn_ids` cell reads **1.33**. walks.tsv has batch 2 runs of 1.320 (rep 1) and 1.329 (rep 4), whose mean is 1.3245, which rounds to **1.32**. That is likely a double rounding (1.3245 to 1.325 to 1.33). The ratio cell (1.00×) is still right. I compared the table mechanically: it has 12 rows × 7 values, and this is the only one of the 84 that disagrees with walks.tsv. Round 3 said every figure matched, and this one slipped through.
- **[severity: prose]** `planning/active/task_plan.md` (the "Verification:" paragraph at the end) says "the SKGT local test pins exists == array mode's **non-empty** ids". This is a claim about the current state, and the test contradicts it. Following decision B2, the test compares against every row of the array result, including the all-NULL-id case, where it asserts that every array is empty. The `lengths > 0` reading is the one B2 rejected.
- **[severity: prose, outside the diff]** The body of issue #281 still says, at line 12, "its booleans equal `lengths(feature_ids) > 0` from the array mode by construction", and line 11 still leaves the shape "to decide in the plan". The shipped mode returns the array walk's row set, so a segment whose only features have NULL ids is a row in it, where `lengths > 0` is FALSE. The shape was decided at the gate. `/gh-pr-merge` step 3b is when this gets reconciled.

No bugs or security issues.

### Round 3's fix, reviewed

- **The shared `walk_from`:** it is one `sprintf()` used by both results. The positional arguments are correct: %1 to %9 map to from_segments, from_features, predicate, ie, aoi_filter, seg ws, seg lc, ft ws and ft lc. The ids SQL is byte-identical to v0.46.0. I checked this independently: the old file came from `git show a49b45b:R/frs_network_features.R`, both versions ran under mocks, and the temp-table name was normalised. That gave 32 configurations (direction × aoi NULL/ADMS × ie × default and custom code columns × two `segment_id_col` values) with 0 diffs. The positive control (ids against exists) does differ.
- **The identity test's regex** is `FROM [^\n]+ a\n[\s\S]*?(?=\s+ORDER BY|\s*$)`. It matches the full span, not a shorter one, in all 8 cases:
  - In the ids query, the outer `FROM (` cannot match, because its line does not end in ` a`. The match starts at `FROM <segments> a`.
  - The lazy body can stop only before the first `\s+ORDER BY` (the prefilter and predicate contain none), or where nothing but whitespace remains (PCRE's `$` without `m`).
  - For each case I compared the extraction with the exists query minus its SELECT line, trimmed, and all 8 were identical. Each ends at the predicate's `)` or at `'ADMS'`, and the lengths were 293 to 657 characters.
  - The two literal assertions (the ie flag and the column wiring) are independent of the code.
- **Mutations I ran in a copy** (`test_file()`, 37 blocks, 172 expectations, 0 skipped):
  - Control: green.
  - exists losing its `aoi` filter: 4 blocks red.
  - exists projecting a fixed `a.id_segment` in place of `segment_id_col`: **green**. The identity test reads only `walk_from`, and every other mocked exists test uses the default id column or a mock that ignores the SQL. Only the live local test (`segment_id_col = "linear_feature_id"`, `skip_on_ci`) would catch it. The shipped code is correct, so this is a coverage note, not a defect. It is the round-3 mechanism again: a check that reads only the shared part of two derivations.
- **`@return`:** the text matches the code. `st_read()` over DBI returns a data.frame, and FILTER over all-NULL ids gives NULL, which `.frs_parse_pg_array()` turns into `character(0)`. The Rd regenerates identically: I regenerated `man/` in a copy, ran `/usr/bin/diff -r` and got no differences, and a word planted in the roxygen reached the Rd.
- **Prose edits:** the README cap sentence matches the tsv. Batch 3's two `exists_base_sql` rows are `timed_out TRUE`, ending at 01:21:22 and 01:26:23, 5 minutes apart. No other row timed out. The script header's env-var sentence matches `out_dir`, `forms`, `views` and `timeout_ms`.

## Enumeration

I walked R/frs_network_features.R, both test files, the data-raw script, the log README, walks.tsv, the three plan JSONs, NEWS 0.47.0, the research section and header, research/README.md, the Rd, DESCRIPTION and CITATION.cff, plus planning task_plan, findings and progress, issue #281's body and link#394's body. **61 pairs; 3 fail** (#40, #60, #61).

**Code against code**
1. exists `walk_from` vs ids `walk_from`: one shared object, so they agree by construction.
2. New ids SQL vs v0.46.0's: independent (old file from git). 32 configurations, 0 diffs, and the control differs. Agree.
3. `cols_segments` (temp-table projection) vs the `a.` columns the walk reads: agree.
4. `cols_features` (prefilter projection) vs the `b.` columns read: agree.
5. exists projection `a.<segment_id_col>` vs ids `a.%1$s` / `GROUP BY d.%1$s`: separate derivations that agree in the code. Only the live test pins this (see the mutation above).
6. ids `ORDER BY` feature code columns vs `walk_from`'s: same arguments. Agree.
7. `names(res)[1] <- segment_id_col` in both branches: agree.

**Code against test oracle**
8. Identity-test regex extraction vs `walk_from`: covers the full span in all 8 cases; not vacuous. Agree.
9. "ids sends the same walk as the default": both sides use one path, so it is not independent, but its name claims only that. Agree.
10. "builds no arrays": the absent patterns, the predicate name per direction and the DISTINCT projection are independent literals. Agree.
11. "keeps the scoped walk": the prefilter oracle calls `.frs_walk_prefilter()` (shared producer) with literal arguments. It tests the wiring and the DDL equality. Agree.
12. "without the scoped walk": literals. Agree.
13. "returns the id column": the mock's result vs the rename and `has_features`, including zero rows. Independent. Agree.
14. Local test, exists vs ids on SKGT: the two share the join, and the fixtures reach the part that differs (repeated ids, NULL ids). The parent reports it passing; I did not run it live.
15. Local test premise, every array empty in the NULL-id case: an absolute check. Agree.

**Roxygen against Rd**
16. Rd regenerated in a copy: identical, and the positive control reached it. Agree.

**Behaviour claims against code or the database**
17. `@param result`, "no array aggregated, no `ORDER BY`": agrees with the SQL.
18. `@param result`, "exactly the rows ids returns": shared walk, DISTINCT vs GROUP BY, NULL segment ids give one row in each. Agree.
19. `@return` ids, "a data frame": agrees with `st_read()`.
20. `@return` exists, `has_features` and the NULL-id row with an empty array: agree.
21. `@description`'s exists sentence: agree.
22. `@examples` `setequal()`: the same arguments as the first call. Agree.
23. NEWS bullets 1 and 2, including "same SQL as 0.46.0": agree (see #2).
24. Research "Existence walks" paragraph 1: agree.
25. Research and README, "an unread `array_agg` is replaced with NULL": I ran a plan-only `EXPLAIN (VERBOSE)` on SALR (upstream, no temp table). Without the pairs sum it gives `Output: a.id_segment, NULL::text[]`; with `sum(cardinality())` it gives `array_agg(...)`. Agree.
26. README, "PostgreSQL 17.5": `SHOW server_version` is 17.5. Agree.
27. Code comments at `walk_from` and the exists branch: agree.

**Script header against script behaviour**
28. `include_equivalents = TRUE` in the captured forms, the candidates (`true, 1`) and `timed_fn`: agree.
29. The eight form definitions vs `walk_sql()`, `candidate_sql()` and `timed_fn()`: agree.
30. The ids digest reads only ids; the ids_arrays digest is `sum(cardinality)`: agree.
31. The digest definition vs `digest_sql()`'s `ORDER BY`. The fn digest (R formatting) vs the SQL digest (`::text`) are independent derivations, and they agree on all 12 walks in the tsv.
32. Run order A B C C B A vs `order_runs`, and the first form must be an ids form: agree.
33. 30-minute default timeout, censored rows, the skipped second ids run: agree.
34. `FRESH_PG*` defaults vs `helper-db.R` `frs_fwapg_conn()`: the five defaults are identical. Agree.
35. Idle-database refusal and `NF281_ALLOW_OTHERS`: agree.
36. The env-var paragraph (round-3 fix): agree. `NF281_EXPLAIN` also uses FORMAT JSON and skips the fn forms, which "each SQL form" covers.
37. Usage default groups (SALR, CHWK, LFRA): agree.
38. "Every form of a walk must give the same digest": the script records it and does not assert it; the tsv agrees.
39. The scope is built once per group and reused: agree.

**walks.tsv and the plans against prose**
40. README Results table, 84 numeric cells plus 12 pair counts and 4 segment counts, compared mechanically: **FAIL**, 1 cell (SALR ST fn_ids, 1.33 vs 1.32).
41. README batch windows vs `measured_utc`: agree. Batch 2's 00:51 start falls before its first row's end at 00:52:33, and EXPLAIN writes no row.
42. README batch contents (forms × groups) vs tsv row counts per batch: agree.
43. README cap sentence vs the `timed_out` rows: agree.
44. "All twelve walks agree": one digest per walk across 208 rows. Agree.
45. README load rows (two with `others_active` = 1), and "neither differs much" (42.0 vs 39.3 s; 21.29 vs 21.33 s): agree.
46. "Mean of the two runs within one batch": every group has n = 2. Agree.
47. `n_pairs` appears only on ids_arrays rows, and every row has 11 fields: agree.
48. EXISTS 1.1× to 15× vs batch 1 (1.09 to 14.67), and "not run in SETN": agree.
49. "Where the array walk took 2.8 s": ids_arrays batch 4 is 2.84 (ids batch 3 is 2.76). Agree.
50. "Why EXISTS loses" vs the CHWK plans: 14,347; about 5,200 (5,216 per loop); 11.4 s; 8,585; 161,974 pairs in 2.8 s (join node 2,830 ms); hash aggregate to 11,301; 6.1 s and 2.6 s timed. Agree.
51. SETN plan vs prose: 4,829,028; 37.9 s of 45.3 s; external merge 538,912 kB. "Reproduces link#394's 4.83 M and 526 MiB" matches link#394's body (538,912 KiB is 526.3 MiB). Agree.
52. "Up to 15% SQL, up to 20% end to end (21.3 to 17.1 s)": 15.0% (SETN CH) and 19.6% (SETN BT). Agree.
53. NEWS figures (1.00× to 1.24×; 41 vs 50 s; 1.1× to 15×): agree.
54. Research figures, including "rising from group to group" (strictly rising across SALR, CHWK, LFRA, SETN for each of CH, BT and ST): agree.
55. findings.md Measurement figures (0.99 to 1.18; the per-group end-to-end ranges; 50.2 to 40.6 s; 12 walks and 208 rows): agree.

**Metadata**
56. DESCRIPTION 0.47.0 vs the NEWS header: agree.
57. CITATION.cff still reads 0.46.0. The repo's bot regenerates it from DESCRIPTION after merge, so this is the expected lag, not a failure. CLAUDE.md's "Version: 0.40.1" is also stale, but it predates this branch.
58. research/README row and the research header (issues, producer, date) vs the section and the log: agree.
59. The log and script paths named in NEWS and research exist: agree.

**Planning and issue**
60. task_plan Verification, "non-empty ids", vs the local test: **FAIL** (prose).
61. Issue #281 body, `lengths(feature_ids) > 0` and the undecided shape, vs the shipped row set: **FAIL** (prose, outside the diff).
