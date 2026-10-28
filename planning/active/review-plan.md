# Plan review — fresh#272 baseline (Plan agent, 2026-10-28, spawned 18:37 UTC, returned 18:43 UTC)

Read-only review of `task_plan.md` against the issue body, `R/frs_network_features.R`, the tests, the temp-table precedent in `frs_point_snap()`, link's call sites and link's measurement script. Findings verified by the parent before folding: B1 (the test at `test-frs_network_features.R:187-204` mocks only `frs_db_query` and asserts `WHERE a\.watershed_group_code = 'ADMS'`), A1 (link's `lnk_access.R:171-176` creates `<view_schema>.zz_lnk_streams_<aoi>` as a real table), A2 (link's `walks.R:108` and `walk_prefilter.R:109` set `default_transaction_read_only = on` before the mocked call). Folded into `task_plan.md` on 2026-10-28; the fold is noted per item.

## 1. Prefilter correctness (the load-bearing claim)

**Verified, holds.** fwapg `db/schema.sql:2161-2241` (11-arg body) and `:2135-2154` (the 10-arg wrapper fresh calls, with `upstream_route_measure_a = downstream_route_measure_a`, tolerance `1`). Both `CASE` arms:

- Criterion 1 (`include_equivalents` false, :2170-2174; true, :2205-2211) begins `blue_line_key_a = blue_line_key_b AND …` in both arms. Tolerance only moves the measure comparison inside that conjunct. Admitted by `blue_line_key = ANY(ARRAY(SELECT DISTINCT blue_line_key FROM <tmp>))`.
- Criterion 2 (:2177-2199 / :2215-2237) begins `wscode_ltree_a <@ wscode_ltree_b AND (…)`, i.e. `wscode_b` is an ancestor-or-self of `wscode_a`. The third sub-branch ("missed side channels", `wscode_a = wscode_b`) is the self case, k = `nlevel`. `subpath(w, 0, k)` for `k ∈ 1..nlevel(w)` enumerates exactly ancestors-or-self.
- NULLs: a NULL code or blue line makes the predicate NULL (row excluded) and the prefilter NULL (row excluded); a NULL element inside the arrays can only exclude. Superset preserved.

So admitted-set ⊇ answer under both `include_equivalents` values and any tolerance. The `d_set` column of link's `walk_prefilter.tsv` (all 40 rows equal pairwise) corroborates empirically. No finding here.

## 2. Findings

### Blocker

**B1. Existing mocked test breaks and silently changes meaning.** `tests/testthat/test-frs_network_features.R:187-204` ("aoi injects WHERE on watershed_group_code") mocks only `frs_db_query` and passes `conn = "mock"`, `direction = "downstream"`, `aoi = "ADMS"`. On the new path the function will call `.frs_db_execute("mock", "CREATE TEMP TABLE …")` → `DBI::dbExecute("mock", …)` → method-dispatch error before the mock is reached; and the assertion `WHERE a\.watershed_group_code = 'ADMS'` is false by design (the WHERE moves into the DDL). *Fix:* a Phase 1 bullet naming the rewrite (mock both `frs_db_query` and `.frs_db_execute`, pattern `test-frs_break.R:145-173`; assert the WSG filter is in the captured DDL and absent from the walk SQL). The other 12 mocked tests use `aoi = NULL` or `upstream`, so they survive only because of gate decision 2. — **Folded: Phase 1, first bullet.**

**B2. Phase 3 as written cannot run the branch's SQL.** The captured walk SQL names a `frs_tmp_…` relation that exists only if the DDL ran, and the function's `on.exit` drops it before the script could replay. *Fix:* mock `.frs_db_execute` as pass-through-and-record but skip the `DROP` (record it, run it at the end), mock `frs_db_query` to capture, then digest the captured walk against the still-present temp table; time the DDL and the walk separately. For the `main` form, source `git show main:R/frs_network_features.R` into a private env (the old function has no side effects) and capture its SQL the same way. — **Folded: Phase 3, first bullet.**

### Gap

**G1. `SELECT *` in the admitted subquery carries every feature column through the Materialize.** link's `barriers_*_access` views carry `geom`. *Fix:* project only `<feature_id_col>, blue_line_key, downstream_route_measure, <features_wscode_col>, <features_localcode_col>`; the walk reads nothing else. — **Folded: Phase 2.**

**G2. Phase 3 timeouts are not designed for.** The sent form on fresh's documented shape is `> 240 s` (SALR CH) and `> 180 s` (LKEL streams); 4 groups × 3 views × 2 forms × 2 reps under a 10-min cap could be hours, and "every digest pair equal" is then unevaluable. *Fix:* catch the timeout per run, write `seconds = NA, timed_out = TRUE`, continue; when the old form is censored, take its digest from the same SQL text run on the temp-table shape (link's sent form) instead. Record the ratio as "> cap/new" when censored. — **Folded: Phase 3.**

**G3. Phase 3 preconditions on the local Docker are not checked.** `fresh_default.barriers_*_access` are views from `lnk_barriers_views()`; `fresh_default` is link's build. Precedent in fresh (`data-raw/bucket_connected_check.R`, `rear_wetland_floor_check.R`) reads `fresh_default` and `stop()`s when absent. *Fix:* check `pg_namespace` for the schema and `to_regclass()` for each relation, stop naming the link command; connect with the `FRESH_PG*` convention (`helper-db.R:38-47`), not `frs_db_conn()`, which can resolve to the shared instance. — **Folded: Phase 3.**

**G4. Error-path drop is only as good as the transaction state.** If the caller has an open transaction and the walk errors, the `DROP` fails ("current transaction is aborted") and is swallowed; the temp survives until the caller rolls back. The mocked "drop runs when the walk errors" test proves the call is attempted; the live `pg_temp` assertion covers autocommit only. Say so in the test comment. — **Folded: Phase 1.**

### Ordering

**O1. Phase 1 live test group choice is undecided.** Name the group before Phase 1 starts rather than querying at runtime. — **Folded: VICT, 2,147 segments (smallest by count; LKEL 2,382 next).**

**O2. Version bump placement.** NEWS needs Phase 3 numbers and CITATION.cff auto-updates from DESCRIPTION; make Phase 4 explicitly after Phase 3's TSV is committed. — **Folded: Phase 4 heading.**

### Assumption

**A1. "link passes `pg_temp.*`" is not what production does.** `lnk_access.R:171-176` creates `<view_schema>.zz_lnk_streams_<aoi>` as a real table; only the measurement scripts use `pg_temp.zz_walk_streams`. Either way temp-from-temp and temp-from-table both work, and the copy of an already-scoped table is the whole table (0.2 s). — **Noted; task_plan.md did not state the premise, findings.md's "What exploration found" names the scoped table correctly.**

**A2. Session contract now extends to every aoi-scoped downstream call, and link's own measurement scripts violate it.** `walk_prefilter.R:109` and `walks.R:108` set `default_transaction_read_only = on` before the (mocked) call; `CREATE TEMP TABLE` fails under `XactReadOnly` ("cannot execute CREATE TABLE in a read-only transaction"). A caller on a read-only session, replica or transaction-pooled pgbouncer breaks where it used to work. *Fix:* roxygen states it as a requirement with the failure mode; the owed link comment names the two scripts; wrap the DDL and rethrow a message naming the cause. — **Folded: Phase 2 and Owed.**

**A3. "A unique last key" is only unique when `feature_id_col` is.** link's observations call passes `feature_id_col = "species_code"`; duplicates are identical values so order among them is immaterial, but roxygen should say "deterministic when `feature_id_col` is unique", and `@return`'s "mirrors `bcfishpass.load_dnstr`" no longer holds in ties. — **Folded: Phase 2 roxygen bullet.**

**A4. Hardcoded names.** `blue_line_key`, `downstream_route_measure`, `watershed_group_code` are already hardcoded in this function; the plan adds the same names in the DDL and prefilter. Consistent with the function, not with CLAUDE.md's `.frs_opt()` principle, and `.frs_opt()` has no WSG column anyway. Do not widen scope; one sentence in the research file. — **Folded: Phase 4 research bullet.**

### Scope

**S1. `aoi = NULL` leaves the pre-scoped-segments caller on the slow path.** Gate decision 2's rationale is true for a province-wide `segments`, false for a caller passing a one-group working table with `aoi = NULL` (there the issue's prefilter helps with no temp table, while on a province-wide table the InitPlan over 11 M rows would admit everything). Defensible; state it in roxygen ("pass `aoi` to get the scoped path") and in the research section as open. — **Folded: Phase 2 roxygen, Phase 4 research.**

**S2. Added beyond the issue.** The temp table (justified by findings), Phase 3 script + logs, research section, CLAUDE.md bullet, version bump. Nothing the issue asked for is dropped. — No change.

**S3. Redundant work per group in link.** `lnk_pipeline_access()` calls the function up to 6 times with the same `segments`/`aoi`; each call now builds and drops its own temp (0.2 s × ≤ 6). State it in the link comment; link's scoped table also serves its `segments_sql`, so it is not purely redundant. — **Folded: Owed.**

### Acceptance

**AC1. Byte-identity test survives the tie key.** `test-frs_network_features-live.R:72-82` sorts both sides before `identical()`; row counts are order-independent. Caveat: that test now exercises the temp-table path on the shared tunnel; if that endpoint were a transaction pooler the test would fail rather than skip. Acceptable: first signal. — No change.

**AC2. The "drop runs when the walk errors" mock** needs `frs_db_query` to throw and `.frs_db_execute` calls recorded; pattern at `test-frs_break.R:147-173`. — **Folded: Phase 1.**

**AC3. "No `frs_tmp_` table remains"**: query `pg_class` joined to `pg_namespace` restricted to `pg_my_temp_schema()`, on the same connection, so the test neither passes vacuously nor fails on a neighbour's leftovers. — **Folded: Phase 1.**

## Verdict (as returned)

The baseline is sound where it matters: the superset claim is correct against the 11-arg body under both `include_equivalents` arms and any tolerance, the gate decision to materialize the AOI's segments is backed by the exploration's planner evidence, the tie key is harmless to the existing live test, and nothing the issue asked for is dropped. It is not ready to park as the reviewed plan until B1 and B2 change; G1, G3 and A2 should be folded at the same time; the rest are wording and comments.
