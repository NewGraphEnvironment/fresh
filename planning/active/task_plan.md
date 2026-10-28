# Task: frs_network_features(): every walk probes the segments once per feature in the province (#272)

Approved 2026-10-28, parked, resumed the same day under the run-to-PR mandate.

`frs_network_features()` (fresh@v0.43.0; the SQL is unchanged since v0.29.0) joins the
AOI's segments to the whole feature table on `fwa_downstream()`. The planner drives from
the feature side and probes the segments once per feature, through a `BitmapOr` on
`blue_line_key` and `wscode_ltree <@ b.wscode_ltree`. With a province-wide table that is one
probe per feature in the table, whatever the AOI: 7.24 M for link's CH view, 3.48 M for
its BT view, 0.50 M for its crossings. Measured by link#261 on a 241-group `default` build
(evidence in link#393: `data-raw/logs/recompute_cost_261/`, verdict in link's
`research/recompute_cost.md`): these walks are most of link's post-consolidate recompute.

`fwa_downstream()` can only return a feature on one of the AOI's blue lines (criterion 1)
or whose wscode is an ancestor of, or equal to, an AOI segment's wscode (criterion 2,
`wscode_a <@ wscode_b`). Cutting the feature side to those first, through the feature
table's own indexes, returned the same features per segment in all 32 walks link tried, and
a group's walks ran 3.6× (SPAT) to 24.6× (CHWK) faster.

## What exploration found that changes the plan

The sent SQL and the issue's prefilter, run on the local Docker fwapg (the database link
measured on; `fresh_default` schema present), read-only, digests compared:

| shape | sent | issue's prefilter | notes |
|---|---|---|---|
| link's: AOI segments in an indexed, analyzed temp table, CH view, SALR | 16.4 s | 2.9 s | link's `walk_prefilter.tsv` |
| fresh's documented: `fresh_default.streams` (11.3 M rows) + `aoi = "SALR"`, CH view | **> 240 s (timeout)** | not run | planner leaves the segment-driven plan: GiST `@>` probe estimated at 77,961 rows per segment, actual ~314 |
| same, anthropogenic view (0.5 M) | 2.5 s | 2.9 s | prefilter form: planner materializes the admitted set and cross-loops it with the segments (`Rows Removed by Join Filter: 14.8 M`) |
| `fwa_stream_networks_sp` as both sides, LKEL | 15 s warm / 76 s cold | **> 180 s (timeout)** | same cartesian shape, 2,382 × 214,852 |

The issue's form as written only helps when the segments side is a small indexed table
(link scopes the group into one in `lnk_access()`, for exactly this planner problem). On
fresh's own documented shape (a province-wide `segments` with `aoi`) it is neutral to
catastrophic, and the *current* SQL is already catastrophic there for a large view. The
answer is unchanged in every form tried: four digests (SALR CH, SALR anthropogenic, LKEL
streams-as-features; link's nine groups) match the unprefiltered join.

The fix therefore has two parts: (1) the set prefilter from the issue, and (2) the AOI's
segments materialized into an indexed, analyzed session temp table before the walk, so the
planner gets the shape link measured whatever the caller's `segments` table is. fresh
already does session temp tables in `frs_point_snap()` (`.frs_db_write_temp()`,
`.frs_db_execute()` + `on.exit` drop).

## Decided at the gate (owner, 2026-10-28)

1. **SQL form: issue's set prefilter + AOI segments in a session temp table.** Inside
   `frs_network_features()`, when `direction = "downstream"` and `aoi` is set:
   `CREATE TEMP TABLE <frs_tmp_…> AS SELECT <id>, blue_line_key, downstream_route_measure, <wscode>, <localcode> FROM <segments> WHERE watershed_group_code = '<aoi>'`,
   btree on `blue_line_key`, GiST on both codes, `ANALYZE`, then the issue's SQL with the
   temp table as `a` and the admitted features as `b`; `DROP TABLE IF EXISTS` on exit.
   Consequence: an aoi-scoped downstream walk needs one backend for the call and a session
   that can create temp tables (not a read-only transaction, not pgbouncer transaction
   pooling), the contract `frs_point_snap()` already carries. Build cost measured: 0.2 s
   for 11,392 segments.
   - Rejected B: a fenced per-segment prefilter (`CROSS JOIN LATERAL (… WHERE f.wscode = ANY(ancestors of a) OR f.blue_line_key = a.blue_line_key OFFSET 0)`),
     read-only, segment-driven by construction, same digests. 8 s on the SALR CH
     province-wide shape (sent > 240 s) but 7.6 s on link's shape against 2.9 s: it
     re-fetches each candidate feature once per segment where A fetches it once.
   - Rejected C: the issue as written. Fastest on link's shape, regresses fresh's
     documented shape (table above).
2. **`aoi = NULL`**: no temp table, no prefilter, SQL unchanged. The whole table is the
   AOI and the prefilter admits everything.
3. **Tie order**: `b.<feature_id_col>` becomes the last `ORDER BY` key in both directions
   (the issue's "one smaller thing"). A unique last key makes the array order a function
   of the data, not the plan.
4. **`direction = "upstream"` is untouched** (the issue's scope). `fwa_upstream()`'s
   criteria are the mirror (descendant codes), unmeasured; noted in the research file as
   open.

Plan review: `review-plan.md` (Plan agent, 2026-10-28). Its two blockers and the gaps are folded below; each bullet names the finding it answers.

## Phase 1: Tests first (fail on main)
- [x] (B1) Rewrite the existing test "aoi injects WHERE on watershed_group_code" (`tests/testthat/test-frs_network_features.R:187-204`): it mocks only `frs_db_query`, so on the new path `.frs_db_execute("mock", …)` errors before the mock, and its assertion `WHERE a\.watershed_group_code = 'ADMS'` is false by design. Mock both `frs_db_query` and `.frs_db_execute` (pattern: `test-frs_break.R:145-173`); assert the WSG filter is in the captured DDL and absent from the walk SQL. The other 12 mocked tests use `aoi = NULL` or `upstream` and survive only because of gate decision 2
- [x] Mocked SQL-composition tests: downstream + `aoi` captures the temp-table DDL (`CREATE TEMP TABLE`, two GiST + one btree index, `ANALYZE`) through the mocked `.frs_db_execute`, the walk SQL joins the temp table and wraps `features` in the prefilter subquery (`subpath(... , 0, k)`, `generate_series(1, nlevel(`, `= ANY (ARRAY(`, `blue_line_key = ANY`), projecting only the five columns the walk reads (G1)
- [x] Mocked: `aoi = NULL` sends no DDL and no prefilter; `direction = "upstream"` sends no DDL and no prefilter (with and without `aoi`)
- [x] Mocked: per-side code columns thread into the prefilter (`features_wscode_col` on `f.`, `segments_wscode_col` in the `subpath`)
- [x] (AC2, G4) Mocked: the temp table's `DROP` is attempted on exit, including when `frs_db_query` throws (`frs_db_query` mock raises; `.frs_db_execute` mock records). The test comment says this proves the call is attempted, not that the table is gone: inside a caller's aborted transaction the `DROP` fails and is swallowed, and the table lives until the caller rolls back
- [x] Mocked: `ORDER BY` ends in `b.<feature_id_col>` in both directions
- [x] (O1, AC3) Live, local Docker (`local_fwapg()` from `tests/testthat/helper-db.R`): `whse_basemapping.fwa_stream_networks_sp` as both `segments` and `features`, `aoi = "VICT"` (2,147 segments, the smallest group by count; LKEL at 2,382 took 15 s unprefiltered), `linear_feature_id` on both sides. **Changed at implementation:** the group is SKGT, and `features` is every 25th FWA segment province-wide plus NULL-coded copies of every 7th SKGT segment, in an indexed temp table. The whole network made the VICT walk 43 s new / 93 s plain, and in VICT, LKEL and UPET removing a prefilter arm changed no answer, so the test could not see it (`findings.md`, "Which arm a fixture can see"). File: `test-frs_network_features-local.R`. The function's per-segment arrays equal the plain unprefiltered join's (sorted), and afterwards no relation named `frs_tmp_%` exists in `pg_my_temp_schema()` on the same connection (`pg_class` joined to `pg_namespace`, restricted to that schema, so a neighbour's `pg_temp_N` leftovers cannot fail it and an empty result is not vacuous: assert the query itself sees the table while the walk runs, via a mocked `frs_db_query` that checks, or accept the autocommit-only scope and say so)
- [x] Keep `test-frs_network_features-live.R` (bcfishpass ADMS byte-identity) as is: it sorts both sides before comparing, so the tie key cannot change it, and it now proves the new path against bcfishpass's precomputed table (AC1)

## Phase 2: Implement
- [x] `R/frs_network_features.R`: internal `.frs_walk_scope(conn, tmp, segments, aoi, cols…)` (renamed from `.frs_network_features_scope`: lintr's 30-character limit; the name is generated by the caller so the `DROP` is registered before the `CREATE`) builds the temp table (name from `tempfile("frs_tmp_")` as `.frs_db_write_temp()` does), indexes, `ANALYZE`; returns the name. `on.exit` drops it via `.frs_db_execute("DROP TABLE IF EXISTS …")` in a `tryCatch`, mirroring `frs_point_snap()`
- [x] (A2) The DDL runs inside a `tryCatch` that rethrows with the cause named: "`frs_network_features(aoi = …)` builds a session temp table; this session cannot (read-only transaction, standby, or transaction pooler)". The original error is chained
- [x] (G1) Downstream + `aoi`: walk SQL uses the temp table as `a` (no `WHERE`), and `b` is `(SELECT f.<feature_id_col>, f.blue_line_key, f.downstream_route_measure, f.<features_wscode_col>, f.<features_localcode_col> FROM <features> f WHERE f.<wscode> = ANY (ARRAY(SELECT DISTINCT subpath(<wscode>, 0, k) FROM <tmp>, generate_series(1, nlevel(<wscode>)) k)) OR f.blue_line_key = ANY (ARRAY(SELECT DISTINCT blue_line_key FROM <tmp>)))`: only the five columns the walk reads, since the admitted set is materialized and link's views carry `geom`. Keep `whse_basemapping.fwa_downstream(...)` as the join predicate, unchanged
- [x] `b.<feature_id_col>` appended to the `ORDER BY` in `sql_fmt`
- [x] (A2, A3, S1) Roxygen: `@details` section on the prefilter (what it admits and why that is the whole of `fwa_downstream()`'s reach); the session requirement with `aoi` stated as a caller-facing contract with its failure mode (one backend; a session that can create temp tables: not a read-only transaction, not a standby, not pgbouncer transaction pooling); `aoi = NULL` is the unprefiltered walk, so a caller holding a pre-scoped working table passes `aoi` to get the scoped path; the tie key, "deterministic when `feature_id_col` is unique" (link passes `species_code` upstream, where duplicates are identical values). `@return`: the order no longer mirrors `bcfishpass.load_dnstr` in ties. `devtools::document()`
- [x] Unit + live tests green: `Rscript -e 'devtools::test(filter = "network_features")' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5`

## Phase 3: Measure on the function's own SQL
- [x] (B2) `data-raw/network_features_prefilter.R`. **Old form:** `R/frs_network_features.R` at tag `v0.44.0` (main's copy at the time) sourced into a private environment (the old function has no side effects) with `frs_db_query` replaced by a capture, so the SQL main sends is run as text. **New form:** the branch package loaded, `.frs_db_execute` mocked as pass-through-and-record that skips the `DROP` (recorded, run by the script at the end of each walk) and `frs_db_query` mocked to capture, so the captured walk SQL runs against the still-present temp table; the DDL's seconds and the walk's seconds recorded separately and summed. Both forms digested by the same SQL (`md5` of `id:sorted array`, link's `digest_sql`). Local Docker fwapg via the `FRESH_PG*` convention (`tests/testthat/helper-db.R:38-47`), never `frs_db_conn()` (G3). Groups SALR, LKEL, CHWK, LSKE × {`fresh_default.barriers_ch_access`, `barriers_bt_access`, `barriers_anthropogenic_unified`} with `segments = fresh_default.streams` (fresh's documented shape), interleaved old/new/new/old. Output `data-raw/logs/network_features_272/walks.tsv` + README. Refuses when another client backend is active (link's `others()` check)
- [x] (G3) Preconditions checked before any timing: `fresh_default` in `pg_namespace` and `to_regclass()` non-null for each of the three relations (they are views from `lnk_barriers_views()`), else `stop()` naming the link command that builds them, as `data-raw/bucket_connected_check.R` does
- [x] (G2) `statement_timeout` 10 min per run, caught per run: a timed-out run is written as `seconds = NA, timed_out = TRUE` and the script continues. When the old form is censored, its digest comes from the same SQL text run once with `a` as an indexed, analyzed temp copy of the group (link's sent shape, `walk_prefilter.R:95-109`), so every pair still has an oracle; the ratio is recorded as "> cap / new"
- [x] Every digest pair equal; record the ratio per walk

## Phase 4: Record what is known (after Phase 3's TSV is committed, O2)
- [x] `research/fwa_downstream_walk.md`: new section "Prefiltering the feature side", with the two criteria, the planner mechanism (the GiST `@>` estimate drives it off the segment-driven plan; the set prefilter is only safe with a small indexed segments relation; the fenced-lateral alternative and why it loses on link's shape), the Phase 3 numbers, and two open items: upstream (the mirror criteria, unmeasured) and `aoi = NULL` on a pre-scoped working table (S1: the prefilter would help there with no temp table, but on a province-wide table the InitPlan over 11 M rows admits everything). One sentence that the per-side code columns are parameters and `blue_line_key`, `downstream_route_measure`, `watershed_group_code` are FWA names the function already carries (A4). Header `Verified` / `Issues` / `Produced by` updated; `research/README.md` row updated
- [ ] `NEWS.md` entry under `# fresh 0.45.0` (numbers from Phase 3, cites link#261 evidence), `DESCRIPTION` 0.44.0 → 0.45.0 as the branch's final commit
- [x] `CLAUDE.md` Technical notes: one bullet under a new "Network features (`frs_network_features()`)" heading: aoi-scoped downstream walks build a session temp table (one backend), prefilter admits ancestors-or-equal ∪ blue lines

## Owed at the end (reported, done after merge)

- [ ] Comment on link#261 / link#393 that fresh ≥ 0.45.0 carries the prefilter and scopes the AOI itself, so `lnk_access()`'s scoped table (`zz_lnk_streams_<aoi>`, a real table in the view schema) is no longer load-bearing for the walk, though it still serves `lnk_pipeline_access()`'s own `segments_sql` (S3: each of the up to six calls per group now builds and drops its own temp, 0.2 s each). Name the new session requirement and the two link scripts that set `default_transaction_read_only = on` before calling the function (`data-raw/logs/recompute_cost_261/walks.R:108`, `walk_prefilter.R:109`), which would now fail on a real call (A2)

## Validation

- [ ] Tests pass (`devtools::test()` with error grep; live tests against the local Docker fwapg)
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] `lintr::lint_package()` clean on touched files; `devtools::document()` run; `pkgdown::check_pkgdown()` (no new export)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, then `/gh-pr-push`

**How each change is proved.** Equivalence: mocked tests pin the SQL shape; the local Docker live test compares the function to the unprefiltered join on real FWA data; the existing ADMS test compares it to bcfishpass's table; Phase 3 digests compare old and new function SQL on link's views. Speed: Phase 3's interleaved timings, on the function's own SQL, on fresh's documented shape; link's `walk_prefilter.tsv` already covers the temp-table shape. Cleanup: the live test asserts no `frs_tmp_` table survives the call, and a mocked test asserts the drop runs when the walk errors.

## Files

- `R/frs_network_features.R` (the change), `R/utils.R` only if the scope helper is better placed beside `.frs_db_write_temp()`
- `tests/testthat/test-frs_network_features.R` (+ a local-Docker live block in `test-frs_network_features-live.R` or a new `test-frs_network_features-local.R` using `local_fwapg()`)
- `data-raw/network_features_prefilter.R`, `data-raw/logs/network_features_272/`
- `research/fwa_downstream_walk.md`, `research/README.md`, `NEWS.md`, `DESCRIPTION`, `CLAUDE.md`, `man/frs_network_features.Rd`
