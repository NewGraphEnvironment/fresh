# Code-check round 3 (#272)

## Checklist read

- code-check-infra.md (38,115 B): in full.
- code-check.md: all 14 H3s under `## Mechanisms`, prose only (table rows and evidence blocks skipped). Not read: the 28 H3s under "Rules that stand alone", Security, and Spreadsheets/PDFs. None of them names a tool or shape this diff uses.
- code-check-r.md: read 7 sections: "Postgres row order is never fixed…", "`tempfile()` lives in the session tempdir…", "A `function(...)` mock hides…", "`system2(stdout = TRUE)` warns…", "A `data-raw/` script must load the source tree…", "`expect_gt()` and friends take no `info`…", "testthat counts an uncaught error…". About 115 others not read.
- code-check-shell.md, code-check-spatial.md: no section read. The diff contains no shell, sed, git scripting or spatial code (the FWA rules there concern geometry, not ltree walks).

## Verification run

- `devtools::test(filter = "network_features")` from an rsync copy: 125 pass, 0 fail, 0 error, 0 skip. This includes `-local.R` (SKGT) and `-live.R`, which reached a bcfishpass DB and passed with the scoped path.
- Probes against the local fwapg (PostgreSQL 17.5). Scratch SQL is in `/private/tmp/claude-501/-Users-airvine-Projects-repo-fresh/86b387fc-8d4c-4a5d-8b8a-b8faa11efb91/scratchpad/r3_*.sql`.
- `walks.tsv` was recomputed in R (means, ranges, ratios, digest agreement).
- `git diff b8f702c 18d36bc` on walks.tsv shows exactly 8 cells changed, `TRUE` to `NA`.

## Findings

No bug in the R code. Tests pass. The SQL is equivalent to the unprefiltered join on everything except the accepted `''` boundary. I checked this against the live `fwa_downstream` 11-argument body: criterion 1 is `blk_a = blk_b`, criterion 2 is `wscode_a <@ wscode_b`, and `include_equivalents` changes neither. The admitted-set plan is feature-driven and probes the temp table (EXPLAIN, SALR CH). The remaining findings are claims in the text.

- **[fragile: prose contradicts measurement]** `tests/testthat/test-frs_network_features-local.R:16` says "Removing that arm changed no answer pair in VICT, LKEL or UPET". `research/fwa_downstream_walk.md:42-45` says "The ancestor arm matters only where an answer reaches a code that is not one of the AOI's own. The answer pairs only it admits … 0 in CHWK, SAHD and UPET, 22 of 40,495 in SKGT".
  - The code has a single wscode arm, `f.ws = ANY(subpath(s.ws, 0, k), k = 1..nlevel)`, which is ancestor **or equal**. The research section uses that same definition two sentences earlier.
  - The measurement was findings.md's mutation "no ancestor arm (self code only)". That mutation kept the equality part and removed only the strict ancestors.
  - Removing the arm as coded changes many answers. FWA side channels share a wscode on a different `blue_line_key`, and `fwa_downstream` has an explicit "missed side channels on the same watershed code" clause for them. Every-25th-segment features, `include_equivalents = FALSE`, pairs whose feature is on a blue line outside the AOI:
    - LKEL: 77,630 of 83,759
    - CHWK: 69,341 of 124,530
    - SKGT: 24 of 40,495
  - Those pairs are admitted only by the wscode arm, so "only it admits" is 69,341 in CHWK (not 0) and 24 in SKGT (not 22) under the code's arm.
  - The stated numbers are correct only for "strict ancestors that are not one of the AOI's own codes".
  - Fix: name the population the mutation removed, e.g. "restricting the wscode arm to the AOI's own codes changed no answer pair in …" and "pairs reaching a strict ancestor that is not one of the AOI's codes".
- **[fragile: overclaimed error path]** `NEWS.md:8` says "A read-only transaction, a hot standby or transaction pooling now stops with an error naming the cause". `R/frs_network_features.R:92` says the same.
  - Only the five DDL statements inside `.frs_walk_scope()`'s `tryCatch` produce the named error.
  - Under transaction pooling each autocommit statement can go to a different server backend. If all the DDL lands on one backend and the walk (`frs_db_query`, outside the `tryCatch`) lands on another, the caller gets a bare `relation "pg_temp.frs_tmp_…" does not exist`.
  - The `on.exit` DROP can then land on a third backend. The table stays on the first backend's pooled connection until that connection closes.
  - No wrong data results, because the random name cannot match anything. But the "names the cause" claim holds only for failures during the DDL. Either wrap the walk's "relation … does not exist" in the same classed error, or narrow the sentence. The accepted tradeoff's phrase "errors name the cause" rests on this claim.
- **[prose: universal carried from another population]** `NEWS.md:7` says "Before, the planner probed the AOI's segments once for every feature in the table". `R/frs_network_features.R:82-85` says "Unscoped, the planner probes the segments once per feature in the whole feature table, or …".
  - On fresh's documented shape (province-wide `fresh_default.streams` + `aoi`), the anthropogenic walk is segment-driven. EXPLAIN ANALYZE, SALR: Parallel Index Scan on `streams_pkey` outer, Bitmap Heap Scan on barriers inner, `loops=11392`, GiST estimate 77,961 against actual 314.
  - The feature-driven plan appears on CH (EXPLAIN: barriers outer, 3.66 M estimated) and on link#261's temp-table shape. The issue's "once per feature in the province" came from link#261.
  - NEWS's next sentence ("could leave the segment-driven plan") contradicts its own universal. Qualify the first sentence: "on a small segments table, or on the CH/BT views".
- **[prose: wrong fact, safe consequence]** `research/fwa_downstream_walk.md:82` says "`fwa_upstream()`'s reach is the mirror: the same blue line, or a wscode equal to or below the segment's".
  - The live `fwa_upstream` body begins `wscode_ltree_b <@ wscode_ltree_a AND (CASE …)`, with the comment "b is a child of a, always".
  - The same-blue-line test sits inside the AND, so it is not a second arm. A NULL-coded feature on the segment's blue line is never upstream.
  - The reach is the single criterion `wscode_b <@ wscode_a`. A prefilter built from the sentence would be a superset, so this is safe, but the sentence is not a mirror of the downstream one.
- **[prose: wrong window]** `data-raw/logs/network_features_272/README.md:5` gives "(19:40-20:57 UTC)", and findings.md repeats it.
  - The script writes `measured_utc = now()` after each run (`emit` follows `timed_digest`).
  - Row 1 is a 600 s timeout written at 19:40:56Z, so the measurement started about 19:30:56Z. The window is about 19:31-20:57 UTC.
  - Same mechanism: a column's meaning (end time) was read as start time.

## Mechanism

Each error, this round and the two before, is a number or a quantifier measured on one population and then written into text that names a wider or different one. Neither the writer nor the reviewers enumerated the population the sentence names. Earlier instances:

- "SKGT reaches the Fraser" was measured on one segment.
- "40,495 with the fixture" was measured on the every-25th part of the fixture only.
- "timed_out" covered both runs and skips.

This round's instances:

- "removing that arm" was measured with a mutation that removed only part of the arm.
- "probes once per feature" was measured on link's temp-table shape, then stated of fresh's province-wide shape.
- "stops with a named error" holds for the DDL step only, then stated of the whole call.
- "the mirror" was inferred from `fwa_downstream`, then stated of `fwa_upstream`.
- "19:40" is an end timestamp read as a start.

In every case the label in the text (an arm, the planner, the call, the reach, the window) is wider than what the probe measured, and nothing compared the two populations.

## Enumeration

Verdicts: **verified** = I recomputed or probed it this round. **finding** = listed above. **wrong-minor** = wrong but not worth a fix on its own. **unverifiable** = the source is a single-shot probe in findings.md or an external repo, and I did not re-run it.

| # | location | claim | source checked | verdict |
|---|---|---|---|---|
| 1 | NEWS:5 | answer unchanged; "every walk measured returned the same features per segment" | walks.tsv `d_set`: 1 distinct per walk, 12/12 (old censored, so compared against old_scoped) | verified |
| 2 | NEWS:7 | planner probed segments once for every feature | EXPLAIN ANALYZE SALR anthropogenic: segment-driven | **finding** |
| 3 | NEWS:7 | could leave the segment-driven plan on a province-wide table | EXPLAIN SALR CH: barriers outer | verified |
| 4 | NEWS:7 | v0.44.0 did not finish in 10 min on **any** CH or BT walk in 4 groups | walks.tsv: 8 `timed_out=TRUE`, all CH/BT, all 4 groups; timeout 600000 ms | verified |
| 5 | NEWS:7 | new form 0.34 to 8.4 s, DDL included | per-walk means 0.338-8.3545; per-run 0.335-8.572 | wrong-minor: holds for means only, basis not stated (per-run max 8.57 s) |
| 6 | NEWS:7 | temp table 0.07 to 0.7 s | per-run DDL 0.072-0.723 | verified |
| 7 | NEWS:7 | anthropogenic 0.85-4.5 s to 0.17-1.7 s | old 0.847-4.529, new 0.172-1.739 | verified |
| 8 | NEWS:7 | link#261 measured these walks as most of link's recompute | findings.md (link repo) | unverifiable (external) |
| 9 | NEWS:8 + roxygen L92 | read-only / standby / transaction pooling stop with an error naming the cause | code: only the DDL is inside the `tryCatch` | **finding** (true for read-only and standby, partial for the pooler) |
| 10 | NEWS:8, CLAUDE.md | `aoi = NULL` and upstream unchanged, create nothing | unit tests "sends no DDL" pass | verified |
| 11 | NEWS:9 | ORDER BY ends on feature id in both directions; ties ordered the same on every run | code + unit test; equal-key rows carry the same element, so the array is fixed | verified |
| 12 | NEWS:9 | tie order can differ from load_dnstr's | logic | verified |
| 13 | roxygen L66-72 | "only lie downstream when on blue line or wscode ancestor-or-equal" | live `fwa_downstream` 11-argument body | verified |
| 14 | roxygen L74-80 | steps 1-3 (columns copied, btree + 2 GiST + ANALYZE, DROP on exit) | code + unit tests | verified |
| 15 | roxygen L76 | admitted "through the feature table's own indexes" | EXPLAIN SALR CH new: `barriers_wscode_gist_idx` and `barriers_blk_drm_idx` BitmapOr | verified (for indexed tables) |
| 16 | roxygen L81-83 | same answer as the unprefiltered join, whatever `include_equivalents` is | function body: criteria identical under both; SKGT live test passes both; `''` boundary accepted | verified |
| 17 | roxygen L82-85 | unscoped probes segments once per feature in the whole table | as #2 | **finding** |
| 18 | roxygen L85-86 | scoped probes the small table once per admitted feature | EXPLAIN SALR CH new form: Bitmap Heap Scan on barriers outer, `t a` inner | verified |
| 19 | roxygen L93-95 | inside an aborted transaction, DROP fails and the table lasts until rollback | PG semantics: CREATE inside the transaction is undone by rollback | verified |
| 20 | roxygen @return | order is a function of the data when `feature_id_col` is unique | code | verified |
| 21 | R L377 comment | "the admitted set is materialized" | EXPLAIN of the shipped scoped shape: no Materialize node (seen only in the prefilter-only province-wide plan, findings) | wrong-minor (projection still useful) |
| 22 | R L376 comment | `IN (SELECT …)` read the whole table in link#261 | findings.md (link) | unverifiable (external) |
| 23 | CLAUDE.md L258 | prefilter = "the whole of `fwa_downstream()`'s reach" | function body | verified |
| 24 | CLAUDE.md L259, research L39 | blue-line arm redundant on FWA codes, "no blue line carries two wscodes (0 rows)" | probe: 0 blue lines with >1 distinct wscode; 0 NULL wscodes in `fwa_stream_networks_sp` | verified |
| 25 | CLAUDE.md L259 | `fwa_downstream` accepts a feature on the segment's blue line with NULL codes | body: criterion 1 reads no codes; `true OR NULL` is true | verified |
| 26 | test-local L9-12 | SKGT streams on Skagit `970` or placeholders, except one 30 m connector 868144510 coded `100.111269` | probe: 970 has 6,914, 999 has 20, 100.* has 1 (868144510, 30.4 m, edge 1450 "Construction line, connection") | verified |
| 27 | test-local L11 | the Fraser (`100`) has no segment in SKGT | probe: the only `100.*` row is `100.111269` | verified |
| 28 | test-local L13-15, research L44 | 22 of 40,495 pairs, every-25th features | probe: ie=FALSE 22 of 40,495; ie=TRUE 22 of 40,769 | verified for ie=FALSE (the test runs both; unqualified) |
| 29 | test-local L16-17 | removing that arm changed no pair in VICT, LKEL, UPET | mutation was "self code only"; whole-arm removal drops 77,630 LKEL pairs | **finding** |
| 30 | test-local L20-24 | NULL-coded copies are admitted only by the blue-line arm | NULL fails `= ANY`; body | verified |
| 31 | test-local L24-26 | VICT prefilter admits 210 k; walk about 43 s, plain about 93 s | probe: admitted 209,987; timings single-shot in findings | verified (count) / unverifiable (timings) |
| 32 | test-local L1-2 | never on CI | `local_fwapg()` calls `skip_on_ci()` | verified |
| 33 | research L42-45 | ancestor arm matters only for non-own codes; 0 in CHWK, SAHD, UPET; UTRE 1.00 M of 1.05 M | CHWK strict-ancestor 0 verified; whole arm 69,341; SAHD, UPET, UTRE not probed | **finding** (definition); SAHD/UPET/UTRE unverifiable |
| 34 | research L48-49 | GiST probe estimated 77,961 per segment, about 314 actual (SALR anthropogenic) | EXPLAIN ANALYZE: rows=77961, actual 314, loops 11392 | verified |
| 35 | research L50 | CH estimate pushes the planner off the segment-driven plan | EXPLAIN SALR CH | verified |
| 36 | research L52-53 | set prefilter alone: 14.8 M rows removed (SALR anthropogenic) | findings 14,833,619 = 11,392 × 1,303 − 10,157 output rows (the 10,157 is from my EXPLAIN) | verified (arithmetic) |
| 37 | research L53 | streams-as-features LKEL > 3 min | findings single shot | unverifiable |
| 38 | research L54-55 | link#261 / `lnk_access()` use a temp table in production | findings quote of link | unverifiable (external) |
| 39 | research L57-58 | temp table 0.07-0.15 s for 7-14 k segments, 0.7 s for 77 k | DDL per-run 0.072-0.146 (SALR, LKEL, CHWK), 0.665-0.723 (LSKE); segments 7,448-14,347, 77,496 | verified |
| 40 | research L61-64 | lateral fence 8 s vs > 240 s sent; 7.6 s vs 2.9 s on link's shape | findings table (single shot; the 2.9 s is link's) | unverifiable |
| 41 | research table + log README table | all 36 seconds cells and the 4 segment counts | walks.tsv means; probe: SALR 11,392, LKEL 7,448, CHWK 14,347, LSKE 77,496 | verified |
| 42 | research L76 | every walk returned the same sorted arrays "in every form" | d_set agreement among completed forms; `old` returned nothing on 8 walks | wrong-minor ("every completed form") |
| 43 | research L82-83 | `fwa_upstream` reach is the mirror (same blue line OR wscode below) | live `fwa_upstream` body: wscode criterion ANDed always | **finding** |
| 44 | research L86-89 | `aoi = NULL` prefilter over 11 M rows would admit everything | logic (all blue lines admitted) | verified |
| 45 | research L91-92 | blk, drm and wsg hard-coded; code columns are parameters | code | verified |
| 46 | research header | probes in `planning/archive/2026-10-issue-272-network-features-prefilter/` | path does not exist yet; task_plan does not pin the slug | fragile: forward reference that `/planning-archive` must match |
| 47 | log README L4-6 | 19:40-20:57 UTC | `measured_utc` is end-of-run; first row = 600 s timeout ending 19:40:56 | **finding** (start about 19:31) |
| 48 | log README L5 | PostgreSQL 17.5 | `version()` | verified |
| 49 | log README L5-6 | no other client backend active (`others_active` 0 on every row) | walks.tsv all 0; sampled after each run, not during | verified as sampled |
| 50 | log README L8 | `fresh_default.streams` province-wide, 11.3 M rows | reltuples 11,333,133 | verified |
| 51 | log README L16-18 | 8 TRUE rows = 8 timed-out runs; 8 cells corrected by hand | walks.tsv; git diff b8f702c..18d36bc: 8 × TRUE→NA | verified |
| 52 | log README L19-22 | `d_set` agrees 12 of 12; `d_order` differs on SALR CH, CHWK CH and BT old_scoped | walks.tsv | verified |
| 53 | log README L22 | that difference is the tie order the new key fixes | the old and new forms share the first three ORDER BY keys, so only ties can reorder | verified |
| 54 | log README ratios | > 309×, > 888×, > 190×, > 470× | 600 / mean = 308.9, 887.6, 189.7, 469.7 | wrong-minor (lower bounds rounded up) |
| 55 | log README L41-43 | old_scoped 7.9× (LSKE) to 33× (CHWK) slower than new | 7.89 (LSKE CH/BT) to 33.3 (CHWK BT) | verified |
| 56 | data-raw header | v0.44.0 SQL; tag exists | tag v0.44.0 present; file identical to merge-base | verified |
| 57 | data-raw header | interleaving, 10-min timeout, skip semantics, oracle shape, FRESH_PG*, refusal when busy | script code | verified |
| 58 | research README row | covers which features a walk can reach and why a temp table | section content | verified |
