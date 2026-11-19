# fresh#293 — code-check round 6

Reviewed at `40ea542`, working tree clean before and after (`git status --short` empty,
HEAD unchanged). Nothing in the working tree was edited apart from this file. Every
probe and mutation ran in a copy (`DESCRIPTION NAMESPACE .Rbuildignore R man tests inst`)
under the session scratchpad, confirmed byte-identical to the tree with `/usr/bin/diff -rq`
before the runs it was used for. `test-habitat_partition_293.R` was run **once**
(18:48:11Z to 18:49:08Z), with no sweep or other run of it in flight.

## Checklist read

- `code-check-infra.md` — in full, every section and evidence block. Applicable: "Two-statement
  DELETE/INSERT into a persist table is not atomic", "Set `statement_timeout` + `lock_timeout`
  on long DB ops" (the `IF NOT EXISTS` lock paragraph), "Joining on a per-tenant key … is
  cartesian".
- `code-check.md` — `## Mechanisms`: the prose of all 14 H3s, `|` rows and evidence blocks
  skipped. Not read: the 25 headings under `## Rules that stand alone`, Security and
  Spreadsheets/PDFs (index only).
- `code-check-r.md` — read by heading, 7 of 122: "Under `R CMD check`, tests run from a temp
  dir against the INSTALLED package", "`deparse(body(f))` excludes formal defaults…",
  "`deparse()` re-encodes non-ASCII…", "Tests that silently do not run", "A `skip_if_not()`
  skips only its own `test_that()` block", "Postgres row order is never fixed…", "An
  `information_schema` lookup by the literal table name…". 115 not read.
- `code-check-shell.md` — read by heading, 0 of its sections in full; index only. (Met one
  in practice: "A verification command can be shadowed by a shell function or alias" — `diff`
  here is `git diff`; I re-ran the copy check with `/usr/bin/diff`.)
- `code-check-spatial.md` — 0 read; nothing in the diff uses sf, terra, bcdata or GDAL.

## Findings

- **F1 [severity: fragile]** `R/frs_habitat_classify.R:97-101` (and `man/frs_habitat_classify.Rd:98-102`, `NEWS.md:21`, `research/id_segment_identity.md:152-156`) — "a species' rows that no later run classifies are **never removed** … and **nothing in fresh deletes them**" is false for the whole-group path. With `wsg_code` set, `.frs_persist_delete_sql()` (`R/utils.R:1622-1626`) returns `DELETE FROM <to> WHERE watershed_group_code = '<code>'` with `extra_subset` dropped, so a later wsg-mode run of that group removes every species' rows, including the ones it does not classify. The suite pins that behaviour itself (`test-habitat_partition_293.R:20-26`, "a whole-group delete does not" carry the species predicate), and the same `@param overwrite` paragraph says so two sentences earlier ("with a group code it is that whole watershed group, every species included"). So the exported Rd contradicts itself on the subject of the issue: when rows are deleted. A reader can take the "Not fixed" sentence as a promise that a wsg run keeps another species' rows, which it does not. The limit is real only for custom-AOI runs; each of the four sites needs "no later custom-AOI run", or "until a whole-group run of that group".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **F2 [severity: fragile]** `NEWS.md:19` — "No habitat or `near_river` table carries `linear_feature_id`, so **each** will be given it on the next run and then refused while any row still holds NULL … Re-running each watershed group with `wsg` and no `aoi` backfills them … and a `near_river` table is a cache …, so dropping it is the **cheaper** repair there". A `near_river` table is never given the column. `.frs_near_river_check_shape()` (`R/frs_near_river.R:452-468`) refuses a table whose `linear_feature_id` disagrees with the streams table's, unconditionally and before any write, in wsg mode too (`test-habitat_partition_293.R:343-372` pins the refusal). So for `near_river` there is no backfill route and dropping is not the cheaper repair: it is the only one. Users act on a release note's migration paragraph. The roxygen (`frs_near_river()`'s `@param to`) is correct; only the NEWS sentence is wrong.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **F3 [severity: fragile]** `tests/testthat/test-habitat_partition_293.R:780` — the inline-join enumeration (`pat <- "[A-Za-z0-9_]+[.]id_segment = [A-Za-z0-9_]+[.]id_segment"`) sees one spelling of a join. `CLAUDE.md` ("fails on any join left spelled inline"), `NEWS.md:15` ("fails on any site that still spells a join inline"), `research/id_segment_identity.md` ("fails on any site that spells a join inline"), `.frs_key_match()`'s roxygen (`R/utils.R:1570-1572`) and the test's own comment ("Anything new fails here") all state the wider population. I probed the regex against `deparse()` of five spellings: `h.id_segment = s.id_segment` matches; `h.id_segment=s.id_segment`, `USING (id_segment, watershed_group_code)`, a join broken across a line (`deparse` writes the newline as a literal `\n`) and `%s.id_segment = %s.id_segment` do not (1 of 5). `USING (id_segment, watershed_group_code)` is not hypothetical: `data-raw/near_river_measure_check.R:77,80` joins a `near_river` table that way. **Today the claim holds**: my own grep of `R/` for every `id_segment` equality and every `USING (` finds only the six allowed sites. So this is the instrument being narrower than the sentence it certifies, the mechanism round 5 named, not a defect in the code. Either widen the pattern (`id_segment\s*=`, `USING\s*\(`, the `\\n` form) or narrow the five sentences to the spelling the test sees.
  - **Rule:** code-check.md "A proxy is not the property" ; code-check.md "A fixture that cannot reach the failure mode"

- **F4 [severity: fragile]** `dev/mutation_sweep_sites_habitat_293.csv:27` ("293 predicate key is strictly logical") — the mutant removes two of the guard's three arms. Pattern `(!is.logical(near_river_lfid) || length(near_river_lfid) != 1L ||` becomes `(FALSE ||`, so the guard still reads `!is.null(x) && (FALSE || is.na(x))`. Measured in the copy: under the row's mutant `NA` and `NA_integer_` are still refused with the guard's message, `"TRUE"` and `1` pass, and `c(TRUE, TRUE)` errors with R's `'length = 2' in coercion to 'logical(1)'`. The `is.na()` arm, the first case the guard's own comment names ("isTRUE() would turn NA … into FALSE"), is mutated by no row. The test does cover it. With only `is.na()` removed, `NA` passes with no error, which the `for (bad in list(NA, …))` loop asserts against. So the guard is tested; the sweep just cannot credit that arm. The pattern `  if (!is.null(near_river_lfid) &&` occurs once (`R/frs_habitat_predicates.R:182`), and substituting `  if (FALSE &&` would remove the whole guard in one row.
  - **Rule:** code-check.md "Restore the bug and prove the guard fires"

- **F5 [severity: fragile]** `R/utils.R:1542-1543` — `.frs_lfid_pair()`'s roxygen says it is "the one test behind every [.frs_key_match()] call **and every partition delete**". The first half holds: 18 of the 19 calls take `lfid <- .frs_lfid_pair(...)`, and the overlay call passes it in place. The second half is false. No partition delete reads it. `.frs_persist_delete_key()` chooses the key from `cols_to`/`cols_from` (in `.frs_habitat_target()`, `.frs_persist_streams()` and `frs_near_river()`), and the `near_river` predicate's key comes from `tgt$lfid` (`R/utils.R:133`), not this helper. The logic is equivalent today (both sides carry the column), so nothing misbehaves. But a reader changing `.frs_lfid_pair()` on the strength of this sentence would expect the deletes to follow, and they would not. Internal `@noRd`, doc only.
  - **Rule:** code-check.md "One fact derived twice"

No bug or security finding. 40ea542's fixes themselves hold (Enumeration, items 1-6).

## Mechanism

Six rounds have shared one assumption: **a sentence that quantifies over a population is
taken as certified by whatever instrument sits beside it, without checking that the
instrument's population is the sentence's.** Each round's enumeration was the right
instrument for what it could reach, and was then reported in the sentence's wider words:

- R4 enumerated `.R` files, and the claim covered every caller (Rd examples were outside it,
  which R5 found).
- R5 enumerated callers, and the claim covered every *mode*. This round's first finding is
  the same shape again: "never removed" was checked against custom-AOI runs (where it holds)
  and written for every run (where the wsg path contradicts it).
- The inline-join test enumerates one textual spelling, and is cited for "any join".
- The sweep row enumerates two of three arms, and is labelled for the whole guard.
- `.frs_lfid_pair()`'s roxygen describes the reads, and is worded for the reads and the deletes.

Where it reaches: every sentence in NEWS, CLAUDE.md, roxygen, `research/` and test comments
that carries `every`, `any`, `never`, `nothing`, `each` or `all N`. The enumeration below
walks them. Read it as covering the branch's present-tense claims about behaviour or
coverage. Historical narrative ("before 0.54.0 every group … was deleted") and one-statement
rationale comments were read but not executed, as below.

## Enumeration

**Set:** the present-tense quantified claims about behaviour or coverage that the branch adds
to `NEWS.md`, `CLAUDE.md`, roxygen (exported and `@noRd`), `research/` and test comments,
plus the claims the brief asked me to verify. **Size: 40.** I extracted 153 quantified added
lines by script (`every|each|all|none|nothing|always|never|any|no … is/are/can/left/spans`
on comment and prose lines). That list was reduced by hand: historical narrative, rationale
for a single statement, and restatements of a claim already counted were dropped, and each
member is listed once with its sites. **Verdicts: 35 HOLD, 5 NOT** (items 4, 8, 27, 29, 32 = F4, F3, F2, F1, F5).

Surfaces walked for "every caller" and "every join" claims: `R/` (namespace, parsed or grepped),
Rd examples (`frs_habitat_predicates` examples run in the copy: OK; the other five changed Rd
files are `\dontrun`), vignettes (no habitat join, no `frs_habitat_predicates()` or
`frs_near_river()` call), tests (the 5 predicate test files run, 0 red; partition file
24/0 red/0 skip; connectivity file 18/0/0), `data-raw/` (`predicates_fixture_0410.R` is the
one `near_river_table` caller and runs against a v0.41.0 worktree; the two `near_river`
scripts write their own tables), `inst/` (no `id_segment`).

| # | claim (site) | instrument / check | verdict |
|---|---|---|---|
| 1 | 40ea542: the two predicate examples now pass `near_river_lfid` | ran `tools::Rd2ex()` of `man/frs_habitat_predicates.Rd` in the copy | HOLD |
| 2 | 40ea542: new tests fail when the group arm is dropped | mutant `parts <- c("id_segment",` in the copy: exactly the 2 new tests red (failed, not error), the other 16 of 18 green; unmutated 18/0/0 | HOLD |
| 3 | sweep row "293 key keeps the group": one line, inside `.frs_key_match`, valid R, removes exactly the group | grep: 1 hit at `R/utils.R:1581`, inside `.frs_key_match`; the mutant parses and builds `h.id_segment = s.id_segment` | HOLD |
| 4 | sweep row "predicate key is strictly logical" removes the guard | mutant run: the `is.na` arm survives | **NOT** (F4) |
| 5 | strict check rejects NA, "TRUE", c(TRUE,TRUE), 1 and accepts TRUE/FALSE | probe: all four rejected with the guard's message, plus `NA_integer_`; TRUE and FALSE accepted | HOLD |
| 6 | `.frs_group_required()` roxygen: neither-column network is replaced on `id_segment`, not read | chooser returns `id_segment` with no lfid on either side; wsg mode refused by `anyNA(have)`; `.frs_key_match` and `.frs_near_river_sql` both equate the group | HOLD |
| 7 | CLAUDE.md / NEWS / research / `.frs_key_match` roxygen: **every** habitat-to-streams match is built by `.frs_key_match()` | grep of `R/` for every `id_segment` equality and `USING (`: only the 6 allowed sites remain inline, each read | HOLD |
| 8 | …and the test "fails on **any** join left spelled inline" (same 4 sites + test comment) | regex probe: 1 of 5 spellings | **NOT** (F3) |
| 9 | NEWS: 19 helper calls; the second test fails on any built with the arm switched off | grep: 19 calls (cluster 10, habitat 7, order_child 1, overlay 1); the test pins 19 and the third argument | HOLD |
| 10 | test comment: each `lfid` symbol is set from `.frs_lfid_pair()` | grep: 8 assignments, all from it | HOLD |
| 11 | NEWS: covers connectivity, clustering, `frs_order_child()`, overlay bridge mode | read each | HOLD |
| 12 | NEWS: the cluster tables carry the parent; write-back pins on it | 3 clustering CTE/temp tables carry `s.linear_feature_id` under `lfid`; 3 write-backs use `.frs_key_match("h","c",lfid)` | HOLD |
| 13 | NEWS: counts scoped by the delete key, not the group | classify uses `tgt$key`; the passes use lfid-or-group, which in wsg mode covers the same rows because the table holds the group whole | HOLD |
| 14 | `frs_cluster` @param habitat: **every** join also matches lfid where both tables carry it | 10 calls plus the species `EXISTS` on `part_col` | HOLD |
| 15 | `.frs_connected_waterbody` roxygen: every join is built by the helper | 5 habitat joins via the helper; `q.id_segment = h.id_segment` is temp to habitat, with `h` already pinned (allowed list) | HOLD |
| 16 | `.frs_run_connectivity` roxygen: UPDATEs confined to the ground in `table` | each UPDATE's `FROM table s` plus the key | HOLD |
| 17 | overlay roxygen: bridge mode also matches lfid | `R/frs_habitat_overlay.R:280` | HOLD |
| 18 | NEWS: both targets carry lfid when the streams table does | habitat: CREATE/ALTER; `near_river`: CREATE with it, or refuse | HOLD |
| 19 | NEWS: the delete keys on lfid through the 0.53.0 chooser | `.frs_persist_delete_key()` at all three writers | HOLD |
| 20 | NEWS / roxygen: a group code is checked against the table | `.frs_wsg_code_check()` in classify and `.frs_near_river_check()` | HOLD |
| 21 | NEWS / roxygen: a custom-AOI delete is scoped to the species classified | `extra_subset`; behavioural test `:373` | HOLD |
| 22 | NEWS: delete and inserts are one transaction (both writers) | tests `:405` and `:593` | HOLD |
| 23 | NEWS: 221/0 and 114/20, across 2 to 125 groups | `data-raw/logs/habitat_293/summary.csv` | HOLD |
| 24 | NEWS: 50,808 / 69,956 / 19,148 / 0.38 | `ratio.csv` (0.3769) | HOLD |
| 25 | NEWS: `near_river_lfid` is required whenever a table is given; `FALSE` is 0.53.0's predicate | partition test `:68`; byte-identity test against the 0.41.0 fixture passes with `FALSE` | HOLD |
| 26 | NEWS: no table carries lfid (measured) | `summary.csv` `n_with_lfid` 0, 0 | HOLD |
| 27 | NEWS: **each** table will be given it, and wsg backfills; dropping `near_river` is the **cheaper** repair | shape check refuses `near_river` in every mode | **NOT** (F2) |
| 28 | NEWS / roxygen: the column is added **only** when the streams table has one | `.frs_habitat_target()`, `.frs_near_river_table()` | HOLD |
| 29 | NEWS / classify roxygen / research: rows no later run classifies are **never** removed; **nothing** in fresh deletes them | the wsg-mode delete is unscoped by species (unit test `:20-26`) | **NOT** (F1) |
| 30 | `frs_near_river` @param `to` / `wsg_code`: other ground kept; wsg removes **every** pair in the group | delete SQL for both branches | HOLD |
| 31 | `.frs_null_key_guard` roxygen: **three** writers; key **always** from the chooser | 3 call sites, each passing the chooser's result | HOLD |
| 32 | `.frs_lfid_pair` roxygen: behind every call **and every partition delete** | the deletes use column lists and `tgt$lfid` | **NOT** (F5) |
| 33 | `.frs_persist_delete_sql` roxygen: the rule lives here so the two callers cannot disagree | both callers pass `extra_subset`; the drop is central | HOLD |
| 34 | `.frs_near_river_pairs_in` roxygen: **both** numbers go through `.frs_sql_num()` on write and compare | `d` via `.frs_sql_num`; threshold via the walk's VALUES (`.frs_sql_num`, `:516`) | HOLD |
| 35 | helper-synthetic: **every** cross-group decoy also differs in its parent | `.bkt_habitat_add()` negates; the 2 direct-INSERT OTHR decoys (`test-frs_bucket_connected.R:190`, `test-frs_connectivity_wsg.R:549`) use `-id` | HOLD |
| 36 | connectivity comment: **none** of the earlier blocks fails with the group arm dropped; the two new ones are the first two blocks again | measured (item 2); fixtures compared line by line | HOLD |
| 37 | brief: internal `lfid = FALSE` defaults: **all** internal callers pass it | `R/utils.R:439`, `:603`, `frs_habitat_predicates.R:235,260`; no other `R/` or `data-raw/` caller | HOLD |
| 38 | brief: the inline count and species key choice agrees with **all** writers | writers write lfid iff both carry it; readers' `.frs_lfid_pair` tests the same | HOLD |
| 39 | `.frs_habitat_target` roxygen: the caller builds its DELETE from the one read | classify passes `tgt$cols_to/from` | HOLD |
| 40 | 40ea542 commit: **every** package example was run | the predicates examples run; all other changed examples are `\dontrun` (the commit message itself is immutable) | HOLD |

Tally: 35 HOLD, 5 NOT. Items 4, 8, 27, 29 and 32 are F4, F3, F2, F1 and F5. Items 8 and 4
are instruments narrower than their claims; 27, 29 and 32 are sentences wider than the code.

Not re-flagged (accepted in the brief, checked where asked): items 37 and 38 above;
`to_barriers`; overlay direct mode; no timeout; fresh#308; DESCRIPTION/NEWS version; the
fixed-name tables. Public-repo scan of every changed file: no host, port, tunnel or tailnet
detail and no private repo was added. `review-round4.md:6` carries a local absolute checkout
path (`/Users/<user>/…/fresh-cloud`), a machine path rather than a host. Mention only.
