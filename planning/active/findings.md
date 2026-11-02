# Findings — Custom-AOI jobs delete whole watershed groups from the shared habitat and near_river tables (#293)

## Phase 0 measurement — the `bcfishpass` instance (2026-11-02)

Taken through the `db-newgraph` MCP, which reports `current_database() = bcfishpass`.
This is **not** the instance `frs_db_conn()` reaches in the measurements
`research/id_segment_identity.md` records — there is no `fresh` schema here at all
(`pg_class` join `pg_namespace`, 0 rows for `nspname = 'fresh'`). So this settles the
exposure on one instance only; `frs_db_conn()`'s is still to audit.

Every habitat-shaped table fresh wrote here:

```
                                    rows    groups  species  linear_feature_id
working.streams_adms_habitat       19,303        1        1   absent
working.rt_habitat_rt_co            4,520        1        4   absent
working.habitat_test_brk_default      818        1        2   absent
working.streams_dbg122_habitat        434        1        1   absent
```

No `*_near_river` table exists on the instance (`information_schema.columns`,
`table_name LIKE '%near_river%'`, 0 rows).

**Verdicts.** (1) Every one is single-group, so none can have suffered the loss: a
custom-AOI job's whole-group delete and its reinsert cover the same group. (2) None
carries `linear_feature_id`, so each would meet the migration guard — but each is also
single-group and single-job, so dropping and re-running is the cheap repair rather than
the staged backfill. (3) `working.streams_dbg122_habitat`'s 434 rows match #282's
measured debug AOI (434 rows, 189 base / 245 derived), so these are #282's artifacts,
not production.

## Issue context

**If done:** a custom-AOI job writes and removes only rows for the ground its AOI covers, so a shared habitat table accumulating several watershed groups keeps what each group's own run produced. **If never:** every custom-AOI job silently deletes every habitat row of every group its AOI touches, reinserts only the AOI's own, and reports nothing — the largest known loss in this family.

## Problem

`frs_habitat_classify()` derives its delete scope from the groups present in the working streams table, then deletes those groups **whole** from the shared output:

```r
# R/frs_habitat_classify.R:170-172
wsg_codes <- DBI::dbGetQuery(conn,
  sprintf("SELECT DISTINCT watershed_group_code FROM %s", table))$watershed_group_code

# R/frs_habitat_classify.R:249-255, per code:
DELETE FROM <to> WHERE watershed_group_code = <wsg>
```

In WSG mode that is correct and self-healing: the job segments the whole group, so deleting the group and reinserting is a clean replace. In **custom-AOI mode** the working table holds only the AOI's segments while the groups it names extend far beyond it, so the DELETE removes rows the job will not put back.

`R/frs_near_river.R:155-158` has the identical shape, and its comment states the intent outright:

```r
# A custom AOI need not be one group, so delete every group the table holds.
DELETE FROM <to> WHERE watershed_group_code IN (
  SELECT DISTINCT watershed_group_code FROM <table>)
```

Its target is shared too, not per-job: `R/frs_habitat_classify.R:208` sets `near_tbl <- paste0(to, "_near_river")`.

## Why this is not #231, #277 or #282

Those are all the same mechanism — a predicate keyed on `id_segment` without `watershed_group_code`, so it reaches rows of other groups. This is the **inverse**: the predicate does name `watershed_group_code`, correctly, and the *group set it is given* is too wide. No `id_segment` collision is needed, and adding the group to a join does not fix it. #231's shared-mechanism paragraph does not describe it, and it is in none of its sub-issues.

It is also larger. On the documented custom-AOI example (`man/frs_habitat.Rd:211-217`, `wscode_ltree <@ '100.190442.999098'` into `fresh.streams_habitat`), the AOI is a sub-basin while the five groups it touches are whole watershed groups — so the rows deleted and not replaced outnumber the rows written, by roughly the ratio of those groups to the sub-basin. #282, by comparison, risks a bounded number of `to_streams` rows on the same call.

## Not yet measured

The ratio above is arithmetic from the group and AOI sizes, not a reproduction. Worth establishing before the fix, because it decides whether anything already persisted needs rebuilding:

- Has any run actually used custom-AOI mode against a shared `to_habitat`? The shipped examples do, which is how this surfaced.
- `frs_near_river()`'s target is derived from `to`, so it inherits the same exposure wherever `to` is shared.
- The ratio itself. Measured since: see the section below, which settles the *second* defect at these sites rather than this ratio.

## Narrowing the group set is necessary but not sufficient — measured 2026-11-01

Established while settling #282's delete key, on the database `frs_db_conn()` reaches. **Two separate defects live at these sites, and only the first is the one filed above.**

**1. The scope defect, as filed.** Unchanged: the delete names `watershed_group_code` correctly and is handed a group set wider than the ground the job will reinsert.

**2. `id_segment` is ambiguous on a table built by current code**, so narrowing the group set does not make the delete safe. A real custom-AOI job (464 rows, one group, 189 base / 275 derived ids) was measured against FWA:

```sql
WITH job AS (SELECT DISTINCT id_segment,
               bool_or(id_segment = linear_feature_id) AS is_base
             FROM <the job's rows> GROUP BY id_segment)
SELECT CASE WHEN j.is_base THEN 'base id' ELSE 'derived id' END,
       count(*)
FROM job j JOIN whse_basemapping.fwa_stream_networks_sp n
  ON n.linear_feature_id = j.id_segment
GROUP BY 1;
--> base id    | 189
--> derived id |  81      <- all 81 in the job's OWN watershed group
```

**81 of the 275 derived ids each equal a real `linear_feature_id` in the job's own watershed group.** So a delete scoped to `(id_segment, watershed_group_code)` — the only key these tables can express — still removes rows belonging to other segments of the same group, which the job will not put back. `id_segment` is assigned as `linear_feature_id` for unbroken segments and `max(id_segment) + row_number()` for sub-segments, and the second can land on the first; `research/id_segment_identity.md` has both sites and the measurements.

### The targets cannot express a safer key

Measured on the live tables:

```
fresh.streams_habitat_co  : id_segment, watershed_group_code, accessible,
                            spawning, rearing, lake_rearing, wetland_rearing
<current code>_habitat    : + species_code
```

No `linear_feature_id`, no `downstream_route_measure`. #282 settled on the **parent segment** (`linear_feature_id`) as its delete key, which is unambiguous — no `linear_feature_id` spans a watershed group, 0 measured province-wide — but that key is not available here. So this issue carries a design decision #282 did not:

- **(a)** widen the habitat and `near_river` schemas to carry `linear_feature_id`, and key the delete on it as `to_streams` now does; or
- **(b)** leave the schemas alone and derive the delete scope by joining back through the working streams table, which carries both columns, accepting that the stored key stays ambiguous for every other consumer; or
- **(c)** make `id_segment` unambiguous at assignment, which is the sibling of #218 and reaches far beyond these two functions.

Not decided here. (a) is the one that also fixes joins, and the one with a migration cost.

## Proposal

Delete the rows the job is about to replace, not the groups they belong to. Both functions have the working table to hand, so the scope can come from it directly rather than from the set of group codes it mentions. In WSG mode the group delete stays — it is correct there, and it is the repair path for damage already done.

That fixes defect 1. Defect 2 needs one of (a)–(c) above, so a fix that only narrows the group set must say in `NEWS.md` what it does not cover.

One fixture, in the shape of `tests/testthat/helper-synthetic.R`: a shared output holding one group's rows for ground **outside** a custom AOI, which must survive a custom-AOI classify. A second, for defect 2: a same-group row at an `id_segment` the job's derived ids reach, which must also survive.

Found while reviewing the plan for #282, where a first pass had recorded both sites as "scoped, no change needed" — the audit had asked whether the DELETE named `watershed_group_code` rather than whether the group set was the right scope. Verified 2026-10-28. `research/id_segment_identity.md` has the key measurements.

Relates to #282, #231, #277, #225, and #163 (closed), which audited exactly this question.



## Errors Encountered

| Error | Resolution |
|-------|------------|

## Phase 0 measurement — `frs_db_conn()`'s instance (2026-11-02)

`data-raw/audit_habitat_293.R`, 326 schemas, `statement_timeout = 900000`. Candidates
found by **shape**, not name, so link's `<schema>.streams_habitat` and fresh's own
targets are both counted. Results in `data-raw/audit_habitat_293_tables.csv` and
`data-raw/audit_habitat_293_ratio.csv`.

| shape | tables | multi-group | carry `linear_feature_id` | max groups | rows needing backfill |
|---|---|---|---|---|---|
| habitat | 199 | **0** | 0 | 1 | 23,459,196 |
| near_river | 98 | **21** | 0 | 125 | 1,660,683 |

The row counts move between runs — a second run 20 minutes later read 23,549,635 and
1,661,709 — because other sessions write these schemas while the audit runs. The script
takes 21 s, so re-run it rather than citing a stale figure.

**Every habitat table on the instance is single-group.** So none can have suffered the
loss — a whole-group delete and the job's reinsert cover the same ground — and the
habitat exposure is the shipped documented example rather than anything realised. The
**realised** exposure is `near_river`: 21 tables are shared across 2 to 125 groups, and
every one is reached by the same unscoped group delete (`frs_near_river.R:156-158`).
Its consequence is not a permanent data loss, because the table is a cache a later run
of that group rebuilds, but between those runs a classify over another group reads a
table missing its rows, so every `near_river` predicate silently fails and the habitat
it writes is under-classified.

`seg_ratio_min` / `seg_ratio_max` in the CSV are a loss signature for **habitat** tables
only. On a `near_river` table a low ratio is the expected shape — only segments that
found a river within the distance get a row — so the 0.0049 on
`fresh_default.streams_near_river` (125 groups) says nothing about damage.

### The issue's magnitude claim is wrong, measured

The body says the rows deleted and not replaced "outnumber the rows written, by roughly
the ratio of those groups to the sub-basin". On the documented AOI
(`man/frs_habitat.Rd`, `wscode_ltree <@ '100.190442.999098'`), from the FWA alone:

```
segments inside the AOI                        50,808
segments in the 5 groups it touches            69,956   (ADMS SHUL STHM THOM USHU)
deleted and not replaced, per species          19,148
lost per row written                             0.38
```

The AOI is **73% of the ground of the groups it touches**, not a sub-basin inside them,
so the loss is a fraction of what the job writes rather than a multiple. The defect and
the fix are unchanged; the stated size is not. The issue body is corrected to the
measured figure.

### What this does not change

The read-side hazard the plan review found (B1) is unreachable today on every one of
these tables, and becomes reachable the moment the delete is narrowed — a whole-group
run followed by a custom-AOI run **in the same group** is the shipped repair path and
produces exactly two jobs' rows in one group on a single-group table. Phase 4 stands.

## Three test bugs the narrowed key exposed (2026-11-02)

All three were green before #293 because the old `(id_segment,
watershed_group_code)` key could not tell the difference.

| error | resolution |
|-------|------------|
| `.cds_fixture()` built habitat rows as `(i, i, ...)` while its streams table's `id_segment` is a `row_number()` and its `linear_feature_id` is the real FWA one, so a parent-keyed match found nothing and three connectivity tests reported the flag uncleared | insert the habitat rows **from** `pg_temp.bkt_streams`, so the pair cannot drift |
| a decoy's `linear_feature_id` written with `sprintf("%.0f", held)` came out **0**: `min(linear_feature_id)` on a bigint reaches R as an `integer64`, whose bits a numeric format reinterprets, so the decoy named ground the table does not hold and survived for the wrong reason | `as.character()` and `%s`, with `expect_match(held, "^[0-9]+$")` so a non-digit value fails rather than passing | 
| the progress-line pin stubs `DBI::dbGetQuery` on `frs_habitat_classify` only, and the NULL-key guard reads the target through its own DBI call, so a mock connection raised before the count was built | mock `.frs_null_key_guard` too, and assert the count is scoped by the delete key |

The second is `code-check-r.md`, "A database driver's value is not a base R
type". The first is the sharper one: a fixture that could not reach the failure
mode, and the narrowed key is what made it visible.

## A3: the whole-province delete is cheaper than the 98 it replaces (2026-11-02)

The plan review's assumption A3 was that `frs_habitat_classify(table =
"fresh.streams")` — the shipped whole-table example — becomes an expensive
delete, because a 3.8M-value semi-join replaces 98 cheap column filters.
Measured with `EXPLAIN` (no `ANALYZE`; these are planner costs, not wall clock)
on the database `frs_db_conn()` reaches, `statement_timeout = 120000`:

```
DELETE FROM <target> WHERE linear_feature_id IN (SELECT linear_feature_id FROM fresh.streams)
  Delete on streams  (cost=496772.14..1032265.26 rows=0)
    -> Hash Join (rows=3725058): seq scan + HashAggregate over the same 3.7M rows

DELETE FROM <target> WHERE watershed_group_code = 'BULK'          -- one of 98
  Delete on streams  (cost=0.43..80255.91 rows=0)
    -> Index Scan using streams_wsg_idx (rows=84062)
```

**One semi-join at ~1.03M beats 98 group filters at ~80K each (~7.9M).** So the
new form is cheaper in total for a whole-province run, not more expensive, and
A3's concern does not hold. It is more expensive per *group*, which is why
`wsg_code` exists — a one-group job should pass it, and `frs_habitat()` does.

Two caveats on the numbers. The target here is `fresh.streams` itself, because
no habitat table on the instance carries `linear_feature_id` yet, so the real
delete will run against a wider table with an index on the key, where the plan
will differ. And the hash side estimates 141,596 distinct `linear_feature_id`
out of 3.7M rows, which is statistics rather than the truth; it does not change
the direction.

Measured with the same `integer64` trap as above: `count(*)::bigint` printed
through `cat()` came out `1.87884e-317`. The row count in the table is the
plan's `rows=3725058`, which agrees with the 3,802,814 that
`research/id_segment_identity.md` records.

## The mutation sweep and the integration tests collide (2026-11-02)

Running `dev/mutation_sweep.R` and `test-habitat_partition_293.R` at the same
time makes the end-to-end test error: both drive `frs_habitat()` with the same
`label`s, so both create `working.streams_p293a/b/c` and the barrier and tmp
tables derived from them. The sweep works in a copy of the **package**, not of
the **database**, so the copy does not separate them. This is fresh#279, met
here rather than reasoned about.

So the sweep and that test file run one at a time. Nothing to fix in the
branch; the lesson is that the sweep is not safe to overlap with any
integration test that names a working table as a literal.

## Lint, measured against `origin/main` in a worktree (2026-11-02)

```
               linter main branch delta
   indentation_linter 1396   1465    69
  object_usage_linter   34     84    50
         brace_linter   17     23     6   -> 0 after fixing the new test file
   line_length_linter    6      6     0
   (others)                            0
TOTAL delta: 125
```

- **69 `indentation_linter`** is the class the package carries 1396 of before the
  branch; #282 accepted +70 of the same.
- **50 `object_usage_linter`** is the stale install, not the code: the installed
  `fresh` is **0.52.0**, and `exists(x, asNamespace("fresh"))` is `FALSE` for
  `.frs_lfid_pair`, `.frs_key_match`, `.frs_wsg_code_check`, `.frs_habitat_target`
  **and for `.frs_persist_streams` and `.frs_partition_wsg`, which shipped in
  0.53.0** — so the linter is answering about a release two versions back
  (`code-check-r.md`, "`lintr` also resolves against the installed package").
- **6 `brace_linter`** were mine, all in the new test file: multi-line function
  bodies without braces. Fixed; the delta is now 0.
- `line_length_linter` delta is 0: the 134-character `INSERT` template was already
  over 120 on `main` at 132, so widening it added no lint. A dead `params_sp` local
  that `object_usage_linter` flags in `frs_habitat_classify()` is also pre-existing
  (`origin/main` line 343) and is left alone.

## `/code-check branch` round 1 — nine findings, all verified (2026-11-02)

Full text in `planning/active/review-round1.md`. Every one reproduced before being
fixed; none dismissed. The two that matter most:

- **Three habitat-to-streams joins were still inline in `.frs_connected_waterbody()`**
  (`R/frs_habitat.R`, `origins_sql`, `rearing_segs`, `spawn_upstream`), written with
  the aliases reversed — `s2.id_segment = hr.id_segment`. The same function's
  subtractive UPDATE and its counts *were* converted, so the parent segment was
  enforced when clearing `spawning` and not when choosing rearing origins or spawn
  candidates.
- **And my enumeration test could not see them.** It grepped each parsed body for the
  literal `"id_segment = s.id_segment"`; `grep -c` of that against
  `R/frs_habitat.R` is **0**, so the assertion was `0 == 0` for the one file that
  still had the defect — a proxy for the property, in the instrument built to prove
  the property. It is now a count over the namespace of every
  `<a>.id_segment = <b>.id_segment` against a named, justified allowlist of four, and
  it asserts the regex matches both alias orders before trusting the count.

The other seven:

| finding | why it mattered |
|---|---|
| `grepl("nested transaction", …, fixed = TRUE)` in classify | RPostgres says "Nested transactions not supported." — capital N, plural — so the tolerance the comment promises never fired and any caller already in a transaction was refused. The 0.53.0 sibling in `.frs_persist_streams()` uses `ignore.case`; this copy dropped it |
| `frs_near_river()`'s NULL-key guard ran **after** the delete | when it fires the partition is already gone and the walk never writes it back. Moved into `.frs_near_river_check()`, the writes-nothing pre-flight built for exactly this |
| `extra_subset = if (length(sp_classify) > 0)` | an `if` with no `else` is NULL, which reads as "every species": with no classifiable species the delete wiped the job's ground for all of them while the loop wrote nothing. Reachable — `frs_habitat()` passes an explicit `species` through unfiltered |
| the parent fetch equated `watershed_group_code` | nullable on a non-FWA network, so an equality join silently dropped a NULL-group walk row. `origin_id` alone is exact, which the comment already said |
| the `near_river` delete carried no pair scope | a call for one rule's `(measure, threshold, distance_max)` removed another rule's rows for the same ground and wrote none back, so the other rule's predicate matched nothing. Now scoped to the triples the call walks |
| the lock comment claimed a **deadlock** | there is no cycle: each DDL is its own transaction, so it blocks. Corrected, with what the longer hold actually costs |
| `CLAUDE.md` still said to join on `(id_segment, watershed_group_code)` | the one place left telling the next reader to use the key this branch proves insufficient on a shared table |

Four guards the fixes introduced had no test, so they have one now: the empty-species
skip, an open transaction the caller owns, the `near_river` guard firing before the
delete, and the pair scope. The transaction test also now counts the DELETE, so
"rolled back" is distinguishable from "never ran".

## `/code-check branch` round 2 — five findings, one inside a round-1 fix (2026-11-02)

Full text in `planning/active/review-round2.md`. The predicted shape appeared:

- **`.frs_near_river_pairs_in()` — round 1's finding 5, one axis over, inside the
  fix for finding 7.** The helper added to stop a delete removing rows nothing
  replaces returned `NULL` for an empty pair list, and `.frs_persist_delete_sql()`
  reads `NULL` as *do not narrow*. So the degenerate input would have **widened** the
  delete to every pair on the job's ground. The sibling fix in the same commit met
  the identical R idiom and chose to skip the delete, so the two coupled stores had
  opposite degenerate-input policies. Unreachable today (`ok_num()` refuses an empty
  `threshold` two frames up) — the fail-open was in the helper's own contract.
  Returns `"FALSE"` now.

The other four:

| finding | resolution |
|---|---|
| `frs_near_river()`'s delete + per-pair inserts were **still not one transaction**, while the branch gave exactly that to both siblings — and `.frs_null_key_guard()`'s own roxygen names the three-writer set | wrapped, same shape, same nested-transaction tolerance |
| round 1's fix 6 did not achieve its purpose: the writer stopped equating a nullable `watershed_group_code`, but the **reader** still equates it, so a NULL-group row is written and then unreadable — and for a whole-group run the relocated guard aborts on it offering only "backfill or drop" | refuse the combination once: `.frs_group_required()` stops a network that carries `linear_feature_id` and leaves the group empty, ahead of any write. A network with neither populated is the #225 case and still works. `.frs_wsg_code_check()` refuses a NULL group in its own terms rather than dropping the NA and letting the key guard abort about the wrong column |
| fix 3 falsified the comment the same commit rewrote: with `ignore.case` the caller's-transaction path works, and on it the `CREATE`, the `ALTER` and the indexes run **inside the caller's** transaction and hold to *their* commit | the comment states that case and whose choice it is |
| fix 9 corrected `CLAUDE.md` and left three **exported** functions' pkgdown pages asserting the superseded key — `frs_cluster()`'s even saying a shared table is "therefore safe", the claim the branch disproves — plus two `@noRd` siblings | all five corrected |

Round 2 also verified clean, by replication rather than reading: every `sprintf()`
spec against its args in the eight changed files (0 mismatches) and the argument
order of every changed template by hand; the new enumeration test's scan over all
172 parsed functions, matching the allowlist exactly; fix 7's number formatting
traced end to end; and that fix 4's guard cannot be skipped when it should fire.

### Three near_river tests encoded the pre-#293 behaviour

The full suite after round 1 went FAIL 3, all in `test-frs_near_river.R`, and all
because a call now replaces **only the pairs it walks**: the tests re-ran with a
different `distance_max` into the same table and read the result without filtering
on it, so an earlier pair's rows were still there. The old whole-ground delete is
what made the unfiltered read work. Each assertion now names its own pair's
distance — the fix was right and the tests were asserting the defect.
