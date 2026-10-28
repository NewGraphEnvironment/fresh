# Code-check round 4 (#272)

## Checklist read

- code-check-infra.md (38,115 B): in full.
- code-check.md: all 14 H3s under `## Mechanisms`, prose only (table rows and evidence blocks skipped). Not read: "Rules that stand alone", Security, Spreadsheets/PDFs (no tool or shape in this diff).
- code-check-r.md: 8 sections read: "`on.exit()` at a script's top level never fires", "A `data-raw/` script must load the source tree", "A value compared as `::text`…", "Postgres row order is never fixed…", "`sprintf("%g", x)`…", "An `information_schema` lookup…" (including its correlated-subquery paragraph), "`system2(stdout = TRUE)`…", "A `function(...)` mock hides…". About 103 others not read.
- code-check-spatial.md: 3 FWA sections read ("main stem's downstream end", "`upstream_route_measure`", "main flow is not edge type 1000"); none applies (no geometry or measures in the diff). About 90 others not read.
- code-check-shell.md: no section read; the diff has no shell, sed or git scripting.

## Verification run

- `devtools::test(filter = "network_features")` from an rsync copy: 34 result rows, 130 expectations, 0 failed, 0 error, 0 skipped (the `-local.R` SKGT test and `-live.R` ran).
- Local fwapg probes (scratch SQL in the session scratchpad, `r4_*.sql`): live `fwa_downstream`/`fwa_upstream` bodies (4- and 11-argument); EXPLAIN of the v0.44.0 SQL on province-wide `fresh_default.streams` (CH, anthropogenic) and on an indexed temp copy (CH, anthropogenic); EXPLAIN of the shipped prefiltered walk (anthropogenic, BT); `CREATE TEMP TABLE` under `BEGIN READ ONLY` and under `default_transaction_read_only`; SKGT strict-ancestor codes and the every-25th features on them.
- `walks.tsv` recomputed by hand: every mean, ratio, lower bound, DDL range, digest agreement and the run window.
- One probe of mine (an unprefiltered cross-`include_equivalents` SKGT walk) hit its own 120 s `statement_timeout` server-side and was abandoned. It was not needed: the strict-ancestor feature count below settles the same question.

## Round 3 fixes: verdicts

| fix | check | verdict |
|---|---|---|
| read-only / standby stop with the named error | `BEGIN READ ONLY; CREATE TEMP TABLE …` -> `cannot execute CREATE TABLE AS in a read-only transaction`; same under `default_transaction_read_only=on`; that is the first DDL statement, inside `.frs_walk_scope()`'s `tryCatch` | true |
| pooling: walk can fail on a missing temp table, table may be left behind | code: the walk (`frs_db_query`) is outside the `tryCatch`; the `on.exit` DROP is its own autocommit statement | true as far as it goes; see finding 1 |
| plan sentence ("join order depends on the tables…") | EXPLAIN v0.44.0 SQL: province-wide + CH -> `barriers` outer (3.66 M est.), `streams` inner; province-wide + anthropogenic -> `streams_pkey` outer, GiST probe est. 77,961; temp copy + CH and temp copy + anthropogenic -> `barriers` outer, `t` inner. Both "can" clauses hold | true |
| "Scoped, it probes a small indexed table once per admitted feature" | EXPLAIN shipped SQL, SALR anthropogenic and BT: Bitmap Heap Scan on `barriers` (BitmapOr of the two `= ANY` arms) outer, `t a` inner | true |
| wscode arm = own codes + strict ancestors; 22 counts are strict-ancestor-only | probe: SKGT's strict ancestors that are not SKGT codes are `100`, `970` and `999.*` placeholders. `970` has no segment anywhere; every-25th features on those codes and off SKGT blue lines: 287, none placeholder, 22 on the Fraser below `100.111269`. So the 22 pairs are 22 Fraser features, as the test comment implies | true |
| "Cutting that arm back to the AOI's own codes changed no answer pair in VICT, LKEL or UPET" | findings mutation table: "no ancestor arm (self code only)" passed in VICT, LKEL, UPET | true (matches the mutation now) |
| `fwa_upstream()` always requires `wscode_b <@ wscode_a`; blue-line test inside | 11-arg body begins `wscode_ltree_b <@ wscode_ltree_a AND (CASE …)`; 4-arg body has it in both arms; 10-arg wraps the 11-arg | true |
| window about 19:31-20:57 UTC | row 1 is a 600 s timeout ending 19:40:56Z; last row 20:56:46Z | true |
| lower-bound ratios rounded down | 600/1.9425 = 308.9, 600/0.676 = 887.6, 600/3.1635 = 189.7, 600/1.2775 = 469.7, 600/8.3545 = 71.8, 600/0.804 = 746.3, 600/0.338 = 1775.1, 600/4.333 = 138.5 | true |
| NEWS "0.34 to 8.4 s (mean of two runs)" | CH/BT `new` means 0.338 (LKEL BT) to 8.3545 (LSKE CH) | true |
| R comment no longer says the admitted set is materialized | comment now "a feature view may carry geometry the walk never reads" | true |

## Findings

- **[fragile: prose — the fix moved one sentence and left its sibling]** `R/frs_network_features.R:92-95` (and `man/frs_network_features.Rd:143-146`) against `R/frs_network_features.R:358-360` (pinned by `tests/testthat/test-frs_network_features.R:630`).
  - The roxygen now says a transaction pooler sends the statements to different backends, "so the walk fails because the temp table is not there". The scope error message still lists the pooler among sessions "that cannot create one (read-only transaction, standby, or transaction pooler)".
  - Both are half of the behaviour. Under `pool_mode = transaction` the `CREATE TEMP TABLE` succeeds (a pooler does not stop a temp table being created). The failure depends on where the split falls:
    - If one of the three `CREATE INDEX` statements or the `ANALYZE` reaches another backend, it fails inside `.frs_walk_scope()`'s `tryCatch`, and the caller gets the named `frs_network_features_scope_error`. The walk never runs.
    - If all the DDL lands on one backend and the walk lands on another, the walk fails with a bare `relation "pg_temp.frs_tmp_…" does not exist`.
  - So the roxygen's "so the walk fails" leaves out the named-error case, and the message's "cannot create one" names a mechanism that the roxygen, as just rewritten, says is wrong. No wrong data results either way: the name is random, so every split errors.
  - Fix (prose only): in the roxygen, "…can send the statements to different backends. The call then fails, with the named error if the split falls inside the temp-table step, or in the walk because the table is not there…". In the message, "(read-only transaction, standby, or a transaction pooler that sent a statement to another backend)", and update the test literal.

No bug in the R code. The SQL matches `fwa_downstream()`'s two criteria under both `include_equivalents` values, the DDL and DROP paths are as documented, and the tests pass.

## Rest of the round 3 enumeration, rechecked

- #2/#17 (were findings): the new wording is true (see the plan row above).
- #11/#20: the roxygen says the order is a function of the data "when `feature_id_col` is unique". That is conservative rather than wrong: rows tied on all four keys carry the same element, so the array is fixed either way.
- #21 (was wrong-minor): fixed. The unit-test comment "so a view's geom is not materialized" (test-frs_network_features.R, the "walks the temp table" test) says only that geometry is not carried, which is true of the projection.
- #42 ("every walk returned the same sorted arrays in every form", research): still says "every form". `old` returned nothing on 8 walks. This is wrong-minor, as round 3 marked it, and not re-flagged.
- #46 (archive path): accepted tradeoff.
- Not in round 3's table, checked now:
  - The log README's `d_order` claim ("differs on SALR CH, CHWK CH and BT `old_scoped`") was compared with walks.tsv row by row. It differs on exactly those three and agrees on the other five `old_scoped` rows and on all four anthropogenic walks.
  - `old_scoped` / `new` = 7.89 (LSKE CH and BT) to 33.3 (CHWK BT); the other ratios are 8.85, 10.0, 18.9, 21.5 and 30.5. True.
  - Issue numbers the branch introduces: #265, #272, link#261 resolve to on-topic titles. #259 was already there.
- Unverifiable at probe cost: research "0 in SAHD and UPET … 1.00 M of 1.05 M in UTRE" at `include_equivalents = FALSE`. findings.md does not record the `include_equivalents` value for these runs. UTRE's codes begin at nlevel 4, so its main-stem ancestors lie outside the group, which is consistent with the figure.

## Not flagged (contrived)

- `.frs_walk_prefilter()` names its `generate_series` alias `k` unqualified. A segments table whose id or wscode column is named `k` would make `subpath(s.<col>, 0, k)` ambiguous. That is a loud error, not a wrong answer.
