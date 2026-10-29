# Findings — frs_network_features(): an existence mode (#281)

## Issue context

**If we do it:** a caller that only needs to know whether any feature lies downstream of each segment gets that answer without building and sorting every (segment, feature) pair, and keeps #272's temp table and prefilter. **If we never do:** callers build full arrays and throw them away; in groups where the pairs are many, that build is the walk's cost and #272's prefilter barely moves it.

## Problem

`frs_network_features()` returns, per segment, the array of every feature downstream (or upstream). Some callers reduce that array to one boolean per segment. NewGraphEnvironment/link#394 measured the cost of building what is thrown away: in SETN the CH walk produces 4.83 M (segment, feature) pairs and spills a 526 MiB sort to disk, and #272's prefilter makes that group's walks only 1.2× faster, because the time is in the output, not the probing.

## Proposed

An existence mode on `frs_network_features()`, for example `result = c("ids", "exists")`:

- `"exists"` returns one row per AOI segment with a logical `has_features` (or only the segments that have one, matching the current inner-join shape; to decide in the plan).
- It uses the same `fwa_downstream()` / `fwa_upstream()` predicate, and on the scoped downstream path the same temp table and prefilter, so its booleans equal `lengths(feature_ids) > 0` from the array mode by construction.
- No sort and no `array_agg`; `EXISTS` (or a semi-join) can stop at the first match per segment.

## How to measure

Against the array mode on SALR, CHWK, SETN and LFRA with link's natural barrier views: identical booleans per segment, and the time of each. SETN is the group that should move.

Relates to NewGraphEnvironment/link#394 (lever 1) and NewGraphEnvironment/link#377.


## Found while exploring (2026-10-28, not yet a plan)

- **How link uses the result** (`R/lnk_pipeline_access.R`, v0.69.3): `has_barriers_<sp>_dnstr` and `has_barriers_<src>_dnstr` are `out$id %in% result$id`; zero rows means NA or FALSE by species presence; link renames column 2 (`names(df)[2] <- ...`). So an exists result that keeps one row per segment with a feature, plus a second column, lets link switch by adding one argument. Walks that still need arrays: anthropogenic and dams (`dam_dnstr_ind` reads the first element) and the upstream observations walk (species codes). link caches walks per table across its per-species and per-source loops, so a table used in both roles needs the array form.
- **The SQL** (`R/frs_network_features.R`, 0.46.0): one `array_agg ... ORDER BY ... GROUP BY` shape; the scoped downstream path (#272's temp table and prefilter) only changes the `FROM` sources, so a second shape can reuse it.
- **Open for the plan:** `EXISTS` (stops at the first match per segment, but drives from the segments) vs `SELECT DISTINCT` over the same join (keeps #272's feature-driven plan, no sort of pairs). Measure both on smaller groups (SALR, CHWK, LFRA) before SETN: SETN has 188,554 segments, and a probe of the array form alone on its CH view ran past 10 minutes and was cancelled.
- **Before any timing:** check `pg_stat_activity` for other active client backends; the cancelled probe ran beside another session's query.


## Plan review (review-plan.md), disposition — 2026-10-29

- **B1 (aoi_filter is a full WHERE clause):** moot for the form that ships: the DISTINCT join takes `aoi_filter` after the join exactly as the array walk does. The hand-written EXISTS candidate in the script is on the scoped path only (no aoi_filter there).
- **B2 (NULL feature ids):** decided: exists returns the array walk's *row set* (what link reads, `id %in% result$id`), so a segment whose only features have NULL ids is a row in both, with an empty array under ids. Not `lengths > 0`. The script's oracle digests that row set; roxygen says so; the live test has an all-NULL-id feature table.
- **G1 (zero-row data.frame):** `rep(TRUE, nrow(res))`; the mocked zero-row test now returns a data.frame, and goes red with `res$has_features <- TRUE` (checked).
- **G2 (repeated segment ids):** live test adds SKGT segments with every 5th repeated; exists must return each id once, as GROUP BY does.
- **G3 (NULL segment ids):** DISTINCT gives one NA row, as the array walk's GROUP BY does. Not tested; no FWA segment table has NULL ids.
- **G4:** upstream live case is required (in the test). `aoi = NULL` downstream has no live case (province-wide walk); its composition is pinned by the mocked tests.
- **G5 (SETN oracle if ids times out):** 30 min timeout; if the ids form is censored, report that and compare candidates with each other only — said in the log README.
- **G6:** `result` is the last argument; invalid value tested.
- **G7:** description paragraph added for the exists mode.
- **A1:** the ids digest hashes only the id column (no unnest), but production also pays transfer + R parse: script gains `fn_ids` / `fn_exists` forms that time the function end to end (Phase 4).
- **A2:** form chosen on the scoped path; on `aoi = NULL` / upstream the DISTINCT form is the array walk's own join minus the aggregation, so it does no more work there.
- **A3:** report SETN as measured, no threshold claimed.
- **A4:** acknowledged: equality does not check the prefilter (#272 did).
- **O1:** the script captures the function's own SQL (`exists`) and calls it (`fn_*`).
- **O2:** checked: the ids SQL from this branch is identical to v0.46.0's on all four paths (downstream/upstream x aoi NULL/ADMS), temp-table name normalised (scratch `o2_check.R`, 2026-10-29).

## Measurement: which form, and what it saves (2026-10-29, 00:35-01:58 UTC; revised after code-check rounds 1-2)

Local fwapg, link's `fresh_default` natural barrier views (CH, BT, ST access), `include_equivalents = TRUE`, script `data-raw/network_features_exists.R`, log `data-raw/logs/network_features_exists_281/` (README has the table).

- **Choice: the join form (`SELECT DISTINCT a.id ... INNER JOIN ... ON fwa_downstream(...)`).** Correlated EXISTS against the prefiltered features: 1.1x (SALR) to 15x (LFRA BT) slower than the join, same batch (CHWK CH plan: nested-loop semi-join, ~5,200 materialized features tested per segment, no index; 11.4 s vs 2.8 s under EXPLAIN ANALYZE, 6.1 vs 2.6 s timed). EXISTS against the unprefiltered view: > 300 s on CHWK CH (both runs capped) vs 2.8 s.
- **Saving, end to end through the function:** 1.00x SALR, 1.08-1.11x CHWK, 1.18-1.22x LFRA, 1.22-1.24x SETN (CH 50.2 s -> 40.6 s). SQL alone, arrays built (batch 4): 0.99x-1.18x. The join itself is most of the cost in both forms (SETN CH: 37.9 s of 45.3 s).
- **The issue's premise held only in part.** "The time is in the output" was true of what the exists mode removes (array_agg, sort, transfer, R parse), but here that is at most ~20% of a SETN walk end to end (round 1: the SQL-level `ids` digest let the planner drop the arrays; re-timed as `ids_arrays`). The SETN array walk took about 50 s end to end, not >10 min: link's cancelled probe predates or differs from this setup (not investigated). Sort spill in SETN: checked in batch 4 (01:58 UTC, after another client had held the DB from ~01:26): external merge, 538,912 kB, 4,829,028 pairs, = link#394's figures.
- Every walk's digests agree across all forms (12 of 12 walks, 208 rows). Two rows ran beside one other client backend (SETN CH fn_exists rep 3, SETN BT fn_ids rep 4); neither stands apart from its pair.
- Commit 341a34b's message says EXISTS was "2-13x slower"; SALR's is 1.1x. Immutable; the NEWS and README carry the measured range.

## Code-check round 1 (review-round1.md), disposition — 2026-10-29

- **fragile, real (confirmed by `EXPLAIN (VERBOSE)`: `Output: a.id_segment, NULL::text[]`):** the SQL-level `ids` digest read only the ids, so the planner dropped `array_agg`. Fixed: new `ids_arrays` form digests with `sum(cardinality(feature_ids))` (also records `n_pairs`); re-timed all four groups as batch 4 (01:49-01:58 UTC, others_active 0 throughout). Old `ids` rows kept, labelled. Same-batch SQL ratio 0.99x-1.18x; up to 15% saved (SETN CH 45.0 -> 38.3 s).
- **SETN spill now checked (batch 4 EXPLAIN):** 4,829,028 pairs; sort external merge 538,912 kB (= link#394's 4.83 M / 526 MiB); join 37.9 s of 45.3 s.
- **prose, real:** "mean of two runs" mixed batches -> table rebuilt from one batch per column group; "within 0.1 s" -> dropped; "19%" -> 20%; research 11.4 vs 2.8 s now labelled `EXPLAIN ANALYZE`, timed 6.1 vs 2.6 s given. EXISTS range restated against the join, same batch: 1.1x-15x.
- The waiter's first launch raced the other client (idle at 01:48:45, refused at start); relaunched with a retry on a refusal before any timing.

## Code-check round 3 (review-round3.md), disposition — 2026-10-29

Mechanism named by the reviewer: a check that reads only what two derivations share agrees whatever the differing part does (the id-only digest; prose figures as a second hand derivation of walks.tsv; the exists mode's second hand-written copy of the predicate).

- **fragile, real:** the exists SQL carried its own copy of the `fwa_<dir>()` call; four mutations to it (ie hard-coded false, segment code columns swapped, a/b blocks swapped, feature side reading segment columns) left the mocked file green. Fixed: `walk_from` (FROM, predicate, aoi filter) is built once and used by both results; ids SQL re-checked byte-identical to v0.46.0 on four paths. New mocked test asserts the exists walk's FROM..filter text equals the ids walk's for both directions x aoi NULL/ADMS x include_equivalents, with non-default code columns. Mutations m1-m4 on `walk_from` and m5 (exists reverting to its own predicate with ie false) each turn the mocked file red (2, 4, 2, 4, 1 of 37 blocks).
- **prose, real (my bug):** the `@return` paragraph for exists never landed: an unasserted `str.replace` in the first implementation edit missed on indentation. Added; `\value` now documents `has_features`; "tibble" -> "data frame" (`sf::st_read()` returns one).
- **prose, real:** script header said NF281_VIEWS/FORMS/TIMEOUT_MS keep a run out of the log (only NF281_OUT does); README "30-minute cap, nothing hit" ignored batch 3's 5-minute cap (a sentence written in round 1's fix). Both fixed.
- **caveat, taken:** "no (segment, feature) pair is sorted" depends on the planner choosing a hash for DISTINCT; NEWS and roxygen now say the walk has no `ORDER BY`.

## Code-check round 4 (review-round4.md), disposition — 2026-10-29 — loop ended by enumeration

Round 4 enumerated 61 pairs where one fact is derived twice or a check compares two things (code/code, code/test oracle, tsv/prose, roxygen/Rd, script header/behaviour, NEWS/research/log README, issue body/code); 3 failed, all prose:
- README table SALR ST `fn_ids` 1.33 -> 1.32 (mean 1.3245, double-rounded). After the fix, all 84 cells recomputed from walks.tsv by script (`cells.R`, scratch): 0 differ.
- task_plan Verification said "non-empty ids"; now the array mode's rows.
- Issue #281 body still said `lengths > 0` and "to decide in the plan": body edited (decided shape, row-set semantics, the open question marked resolved, a Result section).
- Coverage gap (no defect): a fixed `a.id_segment` projection in the exists SQL passed the mocked file. Added an assertion with `segment_id_col = "linear_feature_id"`; the mutation now turns 1 of 37 blocks red.
Non-independent agreements listed and accepted by design: "ids same as default", the exists/ids join identity (shared by construction), the prefilter oracle built from the same helper.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `REFUSE: another client backend is active` (01:26 UTC, SETN EXPLAIN) | another client was running array walks on the same DB; spill check dropped rather than add load to it |
| `REFUSE` after two idle checks (01:48 UTC): the other client reconnected between the waiter's check and the script's | waiter retries when the script refuses before timing anything |
| A Python `str.replace` edit silently missed (indentation) and the `@return` paragraph never landed | every later scripted edit asserts `count(old) == 1` |
| `'\\s' is an unrecognized escape` in an `Rscript -e` probe | dropped the regexp from the probe |
