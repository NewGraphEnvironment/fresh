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

| shape | tables | multi-group | carry `linear_feature_id` | groups | rows needing backfill |
|---|---|---|---|---|---|
| habitat | 221 | **0** | 0 | 1 | 23,504,961 |
| near_river | 114 | **20** | 0 | 2 to 125 | 1,695,816 |

**Every count here moves; only the shapes hold.** Three runs over one afternoon read 199,
199 and 221 habitat tables and 23.46M, 23.55M and 23.50M rows, because other work creates
and writes these schemas while the audit runs. What did not move across all three: no
habitat table is shared across watershed groups, every shared table is a `near_river` one,
and **nothing** carries `linear_feature_id`. The script takes 21 s — re-run it rather than
citing a figure from this table. Both ends of the shared-group range have a producer in
`summary.csv` (`groups_min_shared`, `groups_max`); the per-table detail does not, by
design, because it names every schema on the instance.

**Every habitat table on the instance is single-group.** So none can have suffered the
loss — a whole-group delete and the job's reinsert cover the same ground — and the
habitat exposure is the shipped documented example rather than anything realised. The
**realised** exposure is `near_river`: 20 tables are shared across 2 to 125 groups, and
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

### And a defect inside round 2's own fix, found by the suite

Wrapping `frs_near_river()`'s delete and inserts in a transaction (round 2's
finding 11) broke four tests two files away with `current transaction is
aborted, commands ignored until end of transaction block`. The function already
had an `on.exit` that drops its walk temp table, registered **before** the new
rollback handler, and handlers run in registration order: a `DROP` issued inside
an aborted transaction raises, that error propagates out of `on.exit`, the
rollback never runs, and the connection is stuck for every later statement in
the session. `after = FALSE` puts the rollback first; the rollback drops the temp
table anyway, so the `DROP` is then a no-op.

The suite caught this, not a reviewer — which is the argument for running it
between rounds rather than only at the end.

## `/code-check branch` round 3 — the mechanism, an enumeration, and three findings

Full text in `planning/active/review-round3.md`.

**The mechanism behind all fourteen earlier findings: one policy written out in
several places, with each round's fix landing on the copy the finding arrived
through.** Two forms:

- **N implementations of one rule across N writers.** `.frs_null_key_guard()`'s own
  roxygen names the set — three writers — and each carried its own copy of five
  policies. The two older writers agreed, so the third read as the exception, and
  the rounds found one policy at a time: nested-transaction tolerance, guard
  placement, reinsert scope, degenerate scope, one transaction.
- **N restatements of one fact.** The read key, written in `CLAUDE.md`, three
  exported roxygen blocks, two `@noRd` siblings, a research note and two comments.

**Why it did not terminate earlier:** the branch's own termination instrument asks
a narrower question than the property it certifies. It counts literal
`<a>.id_segment = <b>.id_segment`, while the property is "every match of a
segment-level row to a stream segment" — which can also be a `GROUP BY`, a
`USING`, an `IN (SELECT …)`, or a second helper's output.

**The enumeration, seven axes, measured.** Round 3 widened the sweep to five SQL
shapes rather than one; **the superset finds nothing the narrow regex misses
today**, so the count is correct now and it is the question that is narrow. 23
habitat↔streams match sites: 19 built by `.frs_key_match()`, 4 allowlisted inline
functions re-justified, and `.frs_near_river_sql()` as a second implementation.
All three writers now agree on all five policies. No third member of the fail-open
class. All six `.frs_wsg_in()` sites pass the job's own key. `to_barriers` is the
fourth persist target and remains unscoped — that is #294, already filed.

### Three findings, all acted on

| finding | resolution |
|---|---|
| my round-2 comment stated a **false fact about `on.exit`** — that a failing handler leaves the rollback unrun. Measured on R 4.5.2: it does not; the rollback ran in both orders. What the old order lost was the *error message*, 25P02 replacing the real one, which is what broke the four tests | comment corrected to the measured mechanism: rolling back first **ends** the transaction, so the following `DROP` raises nothing. **Landed in round 4's commit, not round 3's — see below** |
| `frs_habitat_predicates(near_river_lfid = FALSE)` defaulted on the **exported** entry point, so a caller re-deriving the predicate got 0.53.0's short key by omission while the table had begun holding two jobs' rows. link's validator calls it exactly that way (`lnk_habitat_validate.R`) | the argument is now **required** when `near_river_table` is given, with a message naming both answers. 14 test call sites and 4 internal ones say which they mean; link#452 extended |
| the sweep list covers 3 of the 19 `.frs_key_match()` call sites, and those 3 are round 1's found instances — written from the instances, not the population | recorded; the 16 remaining are named in `review-round3.md` and the gap is stated rather than papered over |

### Probed and disproved, recorded because it was the strongest remaining candidate

`frs_feature_index()` does `GROUP BY s.id_segment, s.watershed_group_code` and
carries no `linear_feature_id`, so on this branch's premise two jobs' rows would
merge into one row with the union of both segments' feature arrays — and the
enumeration test cannot see it, because it counts equalities and this is a
`GROUP BY`. **It cannot happen:** `fresh.streams` carries a UNIQUE index on the
pair, so a colliding insert aborts and #282's transaction rolls it back. Over the
population of relations carrying all six columns it reads: 322 relations, 3 without
that unique index, and a collision needs a *shared* one among those three. Same
verdict for `frs_network_features()`.

## `workers = 2L` through the mirai path (2026-11-03)

`data-raw/logs/habitat_293/workers2.log`. Three runs into one shared
`to_habitat`, on the documented AOI and a tributary strictly inside it:

```
outer AOI alone                             464 rows, 464 segments
workers = 2L, same ground again             464      <- replaced, not duplicated
workers = 2L, the inner AOI (231 segments)  464      <- the outer's rows outside it survived
```

The third line is #293's promise, proven through the path `frs_habitat()` actually
uses for a multi-group run: a narrower job over ground the table already covers
replaces its own partition and leaves the rest.

**The first attempt failed, and the reason is worth keeping.** `frs_habitat()`'s
mirai workers call `library(fresh)`, so they run the **installed** package, not the
source tree — with 0.52.0 installed every worker rejected `wsg_code` as an unused
argument and the pipeline aborted. So the parallel path cannot be validated until
the branch is installed, and the same stale install is why `lintr` reported 50
phantom `object_usage_linter` hits (`code-check-r.md`, "`lintr` also resolves
against the installed package"). Installed the branch, re-ran, green.


## `/code-check branch` round 4 — two of round 3's three fixes were never written

Full text in `planning/active/review-round4.md`. This is the worst finding of the
review, and it is about me rather than the code.

**What happened.** Round 3's fixes went in as one `python3` script with three
file-writing sections, each guarded by `assert old in s` and each writing at the
end of its section. The second assertion in the **first** section failed, on
whitespace in a roxygen paragraph. So that file was never written, and the two
later sections — the `near_river_lfid` guard and `.frs_habitat_target()`'s index —
were never reached. I then fixed only the paragraph the assertion had named, saw
`parse OK`, and committed a message claiming all three fixes. `findings.md` said
so too.

So for one commit the branch's own record was ahead of its code:

| claimed in `c4edd3d` | actually in `c4edd3d` |
|---|---|
| the `on.exit` comment corrected | still stating the false mechanism |
| `near_river_lfid` required with `near_river_table` | still `= FALSE` at three sites, `man/` rendering the default, `NEWS.md` publishing it |
| the habitat target's `linear_feature_id` indexed when added | absent |

**The mechanism is round 3's own, one axis over:** a fix recorded as made is what
the next enumeration reads instead of re-deriving it. Round 4 caught it only
because its brief named each of the six things round 3 was supposed to have
changed and it checked the tree for each, rather than reading the diff for what
was there.

**What to do differently:** a multi-edit script that asserts must report which
edits it applied, and the edits must be verified against the tree — not against
`parse OK`, which passes on a file nothing was written to. Every fix in this
commit was grepped for after writing.

### Round 4's other findings, all fixed here

- **`after = FALSE` closed only the branch where fresh opens the transaction.**
  Where the **caller** holds one, `began` is `FALSE`, the rollback handler is never
  registered, and the walk-table `DROP` is the only handler — so a mid-walk failure
  raises 25P02 out of it inside the caller's aborted transaction and replaces the
  real error, which is the failure the ordering was meant to fix. The `DROP` is
  wrapped in `try()` now, which covers both branches and is order-independent;
  `after = FALSE` stays because rolling back first is still tidier.
- **Three call sites the mechanical substitution missed**, which is also the proof
  the guard had never run against the suite. One matters: the 0.41.0 byte-identity
  test, whose frozen fixture was built against a v0.41.0 worktree with no such
  formal, so it now asks for `FALSE` explicitly. `data-raw/predicates_fixture_0410.R`
  must stay as it is for the same reason. The third is an internal
  `.frs_rule_to_sql()` call, where the default is deliberate — the guard is on the
  exported boundary.
- **The re-measurement landed on two of four copies of the counts.** The same commit
  that rewrote the table above to 221/114 left a paragraph fifteen lines below
  saying "21 tables are shared", and the durable note still said "199 habitat tables
  and 98 `near_river` tables" under a header dated the day of the 221/114
  measurement. Both corrected, and the note now says the counts move while the `0`
  does not. Round 4 checked `NEWS.md`'s published figures value by value against the
  two committed CSVs: those were correct.

And my own new test for the guard could not fail on its first two attempts: the
fixture species carried no `near_river` rule, so both keys compiled to the same
text. It carries one now, and the "no table, no question" case uses a separate
plain species, because a rule with a pair refuses a NULL table for its own reason.

## The mutation sweep: the four uncaught sites were real, not a narrow filter

The 24-site sweep ran 2026-11-08 22:00 to 2026-11-09 01:34 UTC against a clean
baseline (20 tests, 0 red, 0 skipped, before and after) and returned **exit 1,
20 of 24 caught**. The four uncaught sites were the three `.frs_key_match()`
calls in `.frs_connected_waterbody()` (`R/frs_habitat.R:1828`, `:1870`, `:1871`)
and `after = FALSE` (`R/frs_near_river.R:227`).

I diagnosed all four as artifacts of the narrow `habitat_partition_293` filter,
on the reasoning that the tests which should pin them live in
`test-frs_connectivity_wsg.R`, `test-frs_bucket_connected.R` and
`test-frs_near_river.R`. **That was wrong.** Re-run with a filter spanning all
seven files — baseline 130 tests, 0 red, 0 skipped, measured clean first
because the sweep refuses on any skip — all four were still uncaught, `0 red`
in both mutated runs each.

So the sweep found exactly what it exists to find, and the first reading of its
output explained the finding away. Two separate holes:

### The parent-segment arm of the read side had no test at all

Every test that touched those three joins pinned their **watershed group** arm
(fresh#242): a decoy in another group, which the `watershed_group_code`
equality already excludes whatever `lfid` is. The `linear_feature_id` arm is
this issue's, and only a decoy **inside** the group on another parent can reach
it — the row shape fresh#293 creates by narrowing the delete. Nothing built one.
`.bkt_habitat_add()` negates `linear_feature_id` and defaults to `wsg = "OTHR"`,
so it was already one argument away from the decoy that was missing.

Three behavioural tests now cover the three sites, plus a fourth for the
subtractive clear's own key (`:1794`), which had the same hole:

| site | the decoy | what it would do unkeyed |
|---|---|---|
| `:1828` origins | rearing TRUE on the waterbody segment | becomes a trace origin, trace keeps the segment below |
| `:1870` rearing_segs | the same row | puts the spawning segment upstream of rearing |
| `:1871` spawn_upstream | spawning TRUE on the lake-adjacent segment | lends its cluster's adjacency to the segment 500 m out |
| `:1794` the clear | spawning TRUE on a stripped segment | the clear reaches another job's row and clears it |

`:1871` is only observable under `lake_adjacent = TRUE`. With it FALSE the
habitat row contributes nothing but the `spawning IS TRUE` filter — the
position, the `EXISTS` and the id that reaches the qualifying set all come from
the streams row — and the subtractive clear requires `h.spawning IS TRUE`,
which the row it would wrongly protect does not have. The existing test
"another group's spawning does not lend lake adjacency to this group's cluster"
already built that fixture for the group arm, so the parent-arm case is a second
decoy and a second run inside it rather than a second copy of the lake search.

### 19 call sites, one guard

The namespace enumeration test proves no habitat-to-streams join is left
spelled inline. It says nothing about a join built **through**
`.frs_key_match()` with the parent arm switched off, which is precisely the
mutation — `.frs_key_match("hr", "s2", FALSE)` passes it. Parsing the namespace
finds **19** such calls (measured: 4 in `.frs_connected_waterbody`, 4
`.frs_cluster_both`, 3 each `.frs_cluster_downstream` / `_upstream`, 2
`.frs_distance_filter`, 1 each `.frs_bucket_connected`, `frs_habitat_overlay`,
`frs_order_child`), 18 passing the symbol `lfid` and one passing
`.frs_lfid_pair(conn, to, bridge)` in place. A test now pins that every one of
them takes the arm from the pair test and never from a literal, with the count
pinned so a site cannot be deleted into compliance.

That is the enumeration for the arm. Nineteen sweep rows of one guard would not
have been one — and the static check cannot show the arm changes an answer,
which is why the four behavioural tests stand beside it rather than instead of
it.

### `after = FALSE` was the fourth site, and it is redundant

The sweep could not credit it, and no test can: with round 4's `try()` on the
walk-table DROP in place, both handler orders end identically. Rolling back
first leaves the DROP a no-op on a table the rollback has already un-created;
dropping first raises 25P02 into the `try()`, and the rollback un-creates the
table anyway. There is no observable difference to assert.

Measured the other way round to be sure which of the two does the work: the
`try()`'s own site **is** caught — 1 red in both mutated runs against a clean
99-test baseline, credited to "a near_river failure in a caller's transaction
raises its own error", the test written for it this session. So the `try()` is
load-bearing and the ordering is not.

`after = FALSE` stays in the code, because rolling back before touching the
database again is the right shape; it carries no row in the site list, because
a row no test can turn red is not a guard. Round 4's note that it "stays
because rolling back first is still tidier" was right about the conclusion and
had not yet measured the premise. The code comment now says so.

## The sweep did not hang: the database host stopped answering

The full 25-site run (launched 2026-11-10 04:51:07Z) reached site 9 of 25 at
07:40:29Z — 9 sites in 2 h 49 min, about 19 minutes each, every one caught, against
a baseline of 134 tests, 0 red, 0 skipped. It then spent 7 h 31 min inside site 10
without finishing, and was stopped at 15:11Z.

It was blocked on the network, not looping. Measured at 15:06-15:11Z:

| probe | reading |
|---|---|
| driver R process CPU | 10 min 17 s over 10 h 18 m elapsed — 1.7%, so blocked on I/O |
| its only socket | to the database host, `SYN_SENT` at 15:06Z, `ESTABLISHED` at 15:09Z |
| ping, that host | 33% loss / 2446 ms avg, then 0% loss / 1524 ms avg / 3241 ms max, then 100% loss |
| ping, local gateway, same minutes | 0% loss / 37 ms avg — so the local link is not the cause |
| log output rate | 240 lines/min over sites 1-9, 5 lines/min during site 10 |

A second, independent database client could not acquire a connection
either, which rules out this process's own state.

**Why it presented as a hang rather than as a suite full of skips.** The integration
tests gate on `skip_if_no_conn()`, which skips when a connect *fails*.
`frs_db_conn()` sets no `connect_timeout`, so an unreachable host does not fail — it
blocks, and every gated test waits behind it forever. Filed as fresh#305: with a
timeout set, this window would have produced an honest wall of
skips in minutes instead of a run that could not end. It also means the sweep's
"refuse unless the baseline is 0 red and 0 skipped" guard cannot see this failure
mode at all, because nothing is ever reported.

The 9 credited sites are not reusable: `dev/mutation_sweep.R` writes its results
table only at the end, and a table assembled across a network outage is not evidence
even where the per-site skip counts read 0. The run is redone whole. The partial log
is kept outside the repo.
