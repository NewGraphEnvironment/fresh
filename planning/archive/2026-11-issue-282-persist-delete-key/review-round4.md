# Round 4 review — branch `282-custom-aoi-persist-deletes-other-watersh`

Reviewed at `8bb10f4` (working tree clean, at HEAD). Diff:
`/var/folders/.../codecheck.IBEqKA/branch.diff`, 15 files — `NEWS.md`,
`R/frs_habitat.R`, `R/utils.R`, `data-raw/audit_persist_282.R`,
`dev/mutation_sweep_sites_persist_282.csv`, `man/frs_habitat.Rd`,
`tests/testthat/test-frs_habitat.R`, `tests/testthat/test-utils.R` and the
seven `planning/active/*.md`. `R/frs_feature_index.R` and
`dev/mutation_sweep_sites_feature_index.csv` appear in `git diff main...HEAD`
only because the branch merged `origin/main` ahead of `main`'s current tip
(`merge-base` = `783c04c`); they are 0.52.0 work and out of scope.

## Checklist read

- `code-check-infra.md` — read in full (41,794 bytes).
- `code-check.md` — the prose of every H3 under `## Mechanisms` (14), plus
  "Do not edit files a long test run is reading", "Test the cold/create path
  of idempotent code", "An ordered dispatch makes severity ordering
  load-bearing", "An assertion that matches an interpolated value cannot see
  the claim around it", "A guard's scope, escape hatches, and remedies",
  "Restore the bug and prove the guard fires", "Documentation Staleness".
- `code-check-r.md` — sections naming the tools this diff uses: testthat
  (`Tests that silently do not run`, `testthat counts an uncaught error under
  error`, `A skip_if_not() skips only its own test_that() block`,
  `expect_gt() and friends take no info argument`, `expect_false(identical())`
  cannot fail, `expect_message()` returns the condition, `A function(...) mock
  hides arguments`, `expect_message(regexp = "...$")`, `testthat's failure
  snapshots land in tests/`, `tolerance is RELATIVE`, `Under R CMD check,
  tests run from a temp dir against the INSTALLED package`, `A pkg:: call in
  a test ... if pkg is undeclared`); DBI/Postgres (`A database driver's value
  is not a base R type`, `A value compared as ::text`, `Postgres row order is
  never fixed`, `sprintf("%g") writes Inf and NA`, `Verify a float-formatting
  fix in its consumer`, `An information_schema lookup by the literal table
  name`); `data-raw/` (`A data-raw/ script must load the source tree`,
  `on.exit() at a script's top level never fires`, `Rscript reads a script as
  it runs`); roxygen (`Inserting a helper between a roxygen block and its
  function rebinds @export`, `R CMD build ships every top-level directory`);
  `$ on a list partial-matches`, `[[ on a named ATOMIC vector`,
  `tryCatch(warning =) DISCARDS the value`, `tryCatch() nests its handlers`,
  `paste() with a zero-length argument`, `nzchar(NA) is TRUE`,
  `ifelse() with an all-NA test`, `lintr also resolves against the installed
  package`, `read.delim() quotes by default`, `deparse(body(f)) excludes
  formal defaults`, `deparse() re-encodes non-ASCII`.
- `code-check-shell.md` — `git diff a..b compares TIPS` (used three-dot),
  `grep -c prints the count AND exits 1`, `A failed cd`, `A failed git fetch`,
  `for x in $(cmd | grep …)`, `A verification command can be shadowed`.
  Nothing in the diff is shell.
- `code-check-spatial.md` — `A name is not a key: GNIS_NAME`, `FWA
  upstream_route_measure misses the next segment's start`, `FWA main flow is
  not edge type 1000 alone`, `A Freshwater Atlas main stem's downstream end`,
  `Ask the file about its field names`, `sf: reproject the polygon to get a
  lat/lon bbox`. No terra/sf/GDAL code in the diff; `.frs_resolve_aoi()` was
  read for the row-predicate claim.
- `code-check-python.md` — not applicable, not read.

Work was done in a copy at
`/private/tmp/claude-501/.../scratchpad/pkgcopy`; the repo was never patched.
No database table was created (the existing `working.test_282_*` fixtures are
the suite's own, created and dropped by it).

---

## Enumeration

### 1. Every guard / `stop()` / decision the branch adds or changes

Enumerated by `parse(keep.source = TRUE)` over the changed files and walking
the bodies of the six functions the diff adds or changes
(`.frs_persist_columns`, `.frs_same_relation`, `.frs_partition_wsg`,
`.frs_persist_delete_key`, `.frs_persist_delete_sql`, `.frs_persist_streams`,
plus the three touched sites in `frs_habitat`). **24 sites**, counted at arm
granularity where a guard has two independent arms (round 3 counted 15; the
count rose because round 3's own fix split one arm into two and added the
`regclass` and `dbBegin` sites).

"Sweep" = a row in `dev/mutation_sweep_sites_persist_282.csv` whose pattern
resolves on the current tree.

| # | site | property it must enforce | predicate IS the property? | test that fails if removed | sweep |
|---|---|---|---|---|---|
| 1 | `utils.R:1097-1098` `.frs_validate_identifier(to/from)` in `.frs_persist_columns` | name is a safe identifier | yes | pre-existing (other tests) | no |
| 2 | `utils.R:1115` type-mismatch `stop()` | no shared column differs in type **in the database** | yes — read from `pg_attribute` | yes, `test-utils.R:177` | no (pre-existing site) |
| 3 | `utils.R:1125-1130` ALTER loop over `cols_missing` | target gains every source column | yes | yes, `test-utils.R:168` (`cols_added == "mad_m3s"`) | no |
| 4 | `utils.R:1135` `cols_to = union(cols_to, cols_missing$col)` | the column set the key chooser sees is **post**-alignment | yes | yes, `test-utils.R:172` (`expect_setequal(cols$cols_to, …)`) | no |
| 5 | `utils.R:1159-1161` `.frs_same_relation` body | two schema-qualified names denote one relation | **proxy, declared as such** — exact only for qualified names; the exact test is site 10 | yes, `test-utils.R:494` | via site 9 |
| 6 | `utils.R:1180` `.frs_partition_wsg` | the job owns **all** of the group | yes (`aoi` NULL ⇔ `job_aoi <- w`, verified at `frs_habitat.R:320-327`) | yes, `test-utils.R:603` (4 cases) | yes, row 11 |
| 7 | `utils.R:1224` `if (!is.null(wsg_code))` dispatch | whole-group vs subset | yes | yes, `test-utils.R:819` | via rows 1/11 |
| 8a | `utils.R:1230-1232` wsg-column guard, **`cols_to`** arm | target carries `watershed_group_code` | yes | yes, `test-utils.R:465` | **row 3 is STALE — resolves to 0 lines** (finding 1) |
| 8b | `utils.R:1231` wsg-column guard, **`cols_from`** arm | source carries it | yes | **NO — measured: mutating it to `TRUE` leaves 83/83 green, 0 skipped** | **none** (finding 2) |
| 9 | `utils.R:1247` `in_to != in_from` mismatch `stop()` | both sides share `linear_feature_id`, else refuse rather than fall back | yes | yes, `test-utils.R:438` (both directions) | yes, row 2 |
| 10 | `utils.R:1254` `if (in_to) return("linear_feature_id")` — **the defect site** | FWA tables key on the parent segment | yes | yes, 4 tests incl. the integration test | yes, row 1 |
| 11a | `utils.R:1257` id_segment guard, **`cols_to`** arm | off-FWA fallback has a key | yes | yes, `test-utils.R:457` (neither side has it) | yes, row 4 (mutates the whole `if`) |
| 11b | `utils.R:1257` id_segment guard, **`cols_from`** half of the `&&` | source carries `id_segment` | yes | **NO — no test passes `cols_to` with `id_segment` and `cols_from` without** | none (row 4 kills the site, not the arm) |
| 12 | `utils.R:1279-1280` `.frs_validate_identifier` in `.frs_persist_delete_sql` | ditto | yes | no test passes a bad name to this fn | no |
| 13 | `utils.R:1285` `.frs_same_relation(to, from)` `stop()` | target ≠ source (string form) | proxy by design (see 5) | yes, `test-utils.R:475` (2 cases) | yes, row 5 |
| 14 | `utils.R:1293` `identical(key, "watershed_group_code")` branch | the statement matches the chosen key | yes | yes, `test-utils.R:781` (property over 6 column sets) | via row 8 |
| 15 | `utils.R:1296` `.frs_quote_string(wsg_code)` | the group code is quoted, not pasted | yes | yes, `test-utils.R:407` (`O'HARA`) | yes, row 8 |
| 16 | `utils.R:1323-1324` `.frs_validate_identifier` in `.frs_persist_streams` | ditto | yes | no | no |
| 17 | `utils.R:1338` `regclass` equality `stop()` | target and source are **different relations in the database** | **yes — this is the property** | yes, `test-utils.R:568` (sets `search_path`, passes a bare name) | yes, row 6 |
| 17b | `utils.R:1338` the `length(same) == 1 && !is.na(same)` arms | — | **defensive arms that fail toward pass**; unreachable (`SELECT (a::regclass = b::regclass)` always returns one non-NULL row) | n/a | n/a |
| 18 | `utils.R:1365` NULL-key guard `n_null > 0` | **the target holds no row the delete cannot address** | **yes — `count(*) … WHERE key IS NULL` on the target, every call** (round 1 replaced the "this call added the column" proxy) | yes, `test-utils.R:643-657` — cold **and** warm (3 calls) | yes, row 10 |
| 18b | `utils.R:1365` `length(n_null) == 1 && !is.na(n_null)` arms | — | same shape as 17b; `count(*)` cannot be NULL | n/a | n/a |
| 19 | `utils.R:1361` `key <- .frs_persist_delete_key(…)` | guard and statement name one column | yes — one chooser, not two readings | yes, `test-utils.R:781` + `test-frs_habitat.R:780` | yes, row 9 |
| 20 | `utils.R:1366-1370` `why <- if (key %in% cols$cols_added)` | message names the right cause | yes | warm branch asserted (`"holds rows with no linear_feature_id"`); **cold branch wording not asserted** (harmless — both carry the row count the test matches) | no |
| 21 | `utils.R:1410-1419` `tryCatch(dbBegin, error =)` + `grepl("nested transaction")` | only an already-open transaction may skip the BEGIN | yes (RPostgres raises `Nested transactions not supported.`; matched case-insensitively) | yes, both branches: `test-utils.R:500` (inside a caller's txn) and `:533` (mockery-stubbed connection failure raises, 0 rows written) | yes, row 7 |
| 22 | `utils.R:1420-1430` `if (began) on.exit(if (!committed) dbRollback)` | DELETE+INSERT are one unit of work | yes | yes, `test-utils.R:661-705` (`tag text NOT NULL` forces the INSERT to fail; the row survives) | no (a real test exists) |
| 23 | `frs_habitat.R:336` `partition_wsg = .frs_partition_wsg(w, aoi)` | the wiring, not just the helper | yes | yes, `test-frs_habitat.R:784-790` (`.frs_partition_wsg(` ×1, `spec$partition_wsg` ×2, `wsg_code <- spec$wsg` ×0) | yes, row 12 |
| 24 | `frs_habitat.R:535` and `:680` `.frs_persist_streams(…)` | both paths go through one helper | yes | yes, `test-frs_habitat.R:741-767` (count 2; no `DELETE FROM … watershed_group_code`; `DELETE FROM` count == `blue_line_key IN` count == 2) | yes, rows 13, 14 |

**Counts.** 24 sites. 20 have a test that fails if the site is removed.
2 sites have neither a test nor a resolving sweep row (8b, 11b) — both are
single arms of two-armed guards whose other arm is tested, and both are
unreachable through `frs_habitat()` today (the working table always carries
`watershed_group_code` and `id_segment`). 2 (17b, 18b) are defensive arms over
probes that cannot produce the value they guard against. Sites 1, 12, 16 are
`.frs_validate_identifier()` calls with no local test (covered elsewhere in
the suite).

Measured, not recalled: `sweep_line()`/`sweep_enclosing()` from
`dev/mutation_sweep.R` were run over the committed site list against the
current tree (13 of 14 rows resolve, 1 does not — finding 1), and site 8b was
mutated in the copy and the filtered suite re-run (83 tests, 0 failed,
0 errored, 0 skipped — the mutation is not caught).

### 2. Every test fixture the branch adds

| fixture | reaches | cannot reach |
|---|---|---|
| `test-utils.R:132` `.frs_persist_columns` src/dst (extended) | column alignment, `cols_added`, `cols_to`/`cols_from`, idempotence | constraints, NOT NULL, generated columns |
| `test-utils.R:397-498` pure-string `delete_sql`/`delete_key`/`same_relation` (8 blocks) | every key branch, both mismatch directions, quoting, the string same-relation test, the chooser↔statement property over 6 column sets. **The only proof that runs on CI** (`.github/workflows/R-CMD-check.yaml` calls `flows/r-cmd-check.yaml@v1`, no `services:`, so every DB test skips there) | anything about the database |
| `test-utils.R:500` `working.test_282_txn_*` | `dbBegin` nesting branch inside a caller's transaction | — |
| `test-utils.R:533` `working.test_282_bgn_*` + `mockery::stub(DBI::dbBegin)` | a non-nesting `dbBegin` failure raises and writes nothing | — |
| `test-utils.R:568` `working.test_282_rc_src` + `SET search_path` | `regclass` identity where two unequal strings name one relation (the one reachable way) | — |
| `test-utils.R:603` `.frs_partition_wsg` unit | all four `aoi` shapes | the `frs_habitat()` wiring (site 23 covers it by parsed body) |
| `test-utils.R:614` `working.test_282_persist_*` | NULL-key guard, **cold and warm** (3 calls — the round-1 defect) | — |
| `test-utils.R:661` `working.test_282_atomic_*` + unique index + `tag text NOT NULL` | DELETE+INSERT atomicity; **NOT NULL now reachable** (was not before round 1) | triggers, RLS |
| `test-utils.R:708` `working.test_282_uniq_*` + unique index | idempotent re-run ×3 under **both** keys — the round-2 defect (a data-modifying CTE) | — |
| `test-utils.R:751` `working.test_282_empty_*` | cold path: empty target gaining the key must **not** refuse | — |
| `test-frs_habitat.R:647` `working.persist_282_streams` + unique index + cross-group decoy (`wsg='OTHR'`, `lfid=-999`) | the #282 scenario end to end, sequential path; the collision is asserted live before survival is asserted (step 4), so a no-op delete cannot pass it | the mirai path; `wsg` + `aoi` together |
| `test-frs_habitat.R:734` parsed-body enumeration | both call sites, no stray `DELETE FROM`, the `partition_wsg` wiring, transaction shape — with no database and no `list.files("R")` | runtime behaviour |

**Still unreachable, and whether it matters here:** triggers, RLS,
partitioning, geometry type/SRID constraints and column defaults — **none
matters for this change**: the statement is `DELETE … WHERE <key> …` plus
`INSERT (cols) SELECT cols`, and the only database object that changes its
outcome is a unique index (now carried by three fixtures) or a NOT NULL (now
carried by one). Generated columns would break the INSERT, but identically
before and after this branch (`cols` has always come from the source).
**The mirai path with `workers > 1`** is still exercised by no test; it was
run by hand against the installed branch (`findings.md`, "The mirai path, run
rather than reasoned about" — six assertions, PASS), and the two call sites
are now textually identical and pinned by the parsed-body test. **`wsg` +
`aoi` end to end** is still exercised by no test; covered by the
`.frs_partition_wsg()` unit plus the three parsed-body counts.

### 3. Prose claims asserting a quantity, a universal, or a behaviour

`NEWS.md` 0.53.0, `man/frs_habitat.Rd` `to_streams`, and the roxygen on
`.frs_persist_columns`, `.frs_same_relation`, `.frs_partition_wsg`,
`.frs_persist_delete_key`, `.frs_persist_delete_sql`, `.frs_persist_streams`
and `frs_habitat`. **26 claims.**

| claim | where | verdict |
|---|---|---|
| overwrote by WSG given `wsg`, by `id_segment` otherwise | NEWS | supported — the removed code in the diff |
| custom AOI now keys on `linear_feature_id` | NEWS, Rd, roxygen | supported (`utils.R:1254`) |
| "An AOI is a row predicate … never truncates one at the AOI boundary" | NEWS, Rd | supported — read all four `.frs_resolve_aoi()` arms: `&&` (character), `ST_Intersects` ×3 (sf, blk+measure, table+id); no `ST_Intersection` anywhere. See the note below on the path the sentence names |
| "Every `.frs_resolve_aoi()` arm is a row predicate" | `utils.R:1199-1200` | supported for the four arms, **but a non-WSG character `aoi` does not reach `.frs_resolve_aoi()` at all** — `frs_habitat.R:453-459` and `:621-625` route it as `frs_extract(where = job_aoi)`, which is the path the integration fixture itself uses. Still a row predicate (it is a `WHERE` clause), so the conclusion holds; the stated support is narrower than the set |
| broken sub-segments keep the parent `linear_feature_id` | roxygen, NEWS | supported — `frs_break.R:683-688`: `cols_split_all = c(sid, measures, geom)` with `sid = "id_segment"` (`frs_network_segment.R:220`), so `linear_feature_id` is in `cols_carry` |
| `id_segment` base rows = `linear_feature_id`; only sub-segments get `max + row_number()` | NEWS (0.46.0 correction) | supported — `.frs_add_id_segment()` (`UPDATE … SET id_segment = linear_feature_id`) and `frs_break.R:696-701` |
| no `linear_feature_id` spans a watershed group (0, province-wide) | NEWS, roxygen | measurement, not re-derivable here; scoped to FWA, and the custom-AOI delete's safety rests on exactly that scope |
| 81 of 275 derived ids collided with a same-group `linear_feature_id`; none cross-group; 464-row AOI | NEWS, roxygen | measurement; internally consistent |
| 296 `streams` relations, 0 without a unique index, 198 + 98 | NEWS, roxygen | measurement; 198 + 98 = 296 ✓ (round 3's fix for the loose "every sibling schema's `streams`" — **now bounded**) |
| 259 blue lines span >1 group (#294 context) | NEWS | re-derived by the author 2026-11-01 (`findings.md`) |
| the two job paths had drifted, one quoting and one pasting | NEWS, roxygen | supported — both removed branches are in the diff |
| helper refuses `to_streams` equal to the working table | NEWS, Rd | supported — two tests, two mechanisms (string + `regclass`) |
| refuses a target holding NULL-keyed rows "for whichever of the three keys the run uses" | NEWS | supported (`utils.R:1361-1364` asks the one chooser) |
| "the check asks the target rather than asking whether this call added the column" | NEWS | supported — round 1's fix |
| "The error carries the row count and how to repair it" | NEWS | **count: supported. Repair: not supported for one of the three keys** — when the key is `watershed_group_code`, the named escape ("re-run every watershed group with `wsg` and no `aoi`") is itself refused by the same guard (finding 3) |
| overwrite is one transaction, not a DELETE and an INSERT autocommitted separately | NEWS, Rd, roxygen | supported — with the documented exception that a caller already in a transaction gets no new BEGIN; `frs_habitat()` never is |
| "Not one statement … the insert's uniqueness check would still see the rows the delete is removing" | NEWS, roxygen | supported — round 3's fix removed the stale "one statement" sentence; `R/utils.R:1395-1412` and NEWS now agree |
| "a run that fails leaves the partition as it was" | Rd | supported for the rows; the `CREATE`/`ALTER` ahead of the transaction can still leave an added column, which the guard's own text then names |
| whole-group overwrite unchanged and self-healing; repair group by group | NEWS, Rd | supported — a whole-group run keys on `watershed_group_code`, so NULL `linear_feature_id` rows in not-yet-re-run groups do not block it |
| "until every group has been re-run the rows of the remaining ones hold NULL for it, which a custom-AOI run refuses" | NEWS, Rd | supported (`utils.R:1365`) |
| `wsg` + `aoi`: character ANDed into the group filter, `sf`/list replaces it | NEWS, Rd, roxygen | supported — `frs_habitat.R:320-327` (round 3's fix for "narrows the job to a subset", which was false for the `sf` arm) |
| "It previously deleted the whole group and inserted back only the subset" | NEWS | supported — old `wsg_code <- spec$wsg` |
| `id_segment` is no longer a fallback for an FWA table; one-sided is an error | NEWS, Rd, roxygen | supported (`utils.R:1247-1255`) |
| audit script reports two reference sets, and why | NEWS, script header | supported — `n_missing_all` / `n_missing_guarded`, both as `NOT EXISTS` set differences (round 3's fix for the differenced-counts shape and the `frs_extract()`-applies-guards misattribution) |
| `.frs_validate_identifier()` "admits only `[A-Za-z_][A-Za-z0-9_.]*`" | `utils.R:1143` | supported — exactly that regex (`"*"` is an extra early return, irrelevant to a table name) |
| `.frs_persist_delete_sql()` "is a pure string builder with no connection so that the delete-key proof runs on CI" | `utils.R:1153` | supported — no `conn` formal, and R-CMD-check declares no Postgres service |

**Counts.** 26 claims. 24 supported as written. 1 supported but on narrower
evidence than the sentence names (the `.frs_resolve_aoi()` universal).
1 not supported for one of three keys (the NULL-guard remedy — finding 3).
Round 3's four unsupported claims are all fixed, and the prose those fixes
added introduced no new unsupported claim beyond finding 3's remedy sentence,
which is round 3's own addition.

### 4. The mutation-sweep site list

`dev/mutation_sweep_sites_persist_282.csv` — 14 rows, 13 resolving.

| row | label | resolves? | guard it is for |
|---|---|---|---|
| 1 | 282 parent-segment key | `utils.R:1254` in `.frs_persist_delete_key` | site 10 |
| 2 | 282 key mismatch errors | `utils.R:1247` | site 9 |
| 3 | 282 wsg column required | **NO — 0 lines match** | site 8a |
| 4 | 282 no key errors | `utils.R:1257` | site 11a |
| 5 | 282 target not source | `utils.R:1285` | site 13 |
| 6 | 282 target not source by regclass | `utils.R:1338` | site 17 |
| 7 | 282 only a nested txn skips the transaction | `utils.R:1414` | site 21 |
| 8 | 282 wsg code quoted | `utils.R:1296` | site 15 |
| 9 | 282 guard asks the chooser | `utils.R:1361` | site 19 |
| 10 | 282 null-key guard | `utils.R:1365` | site 18 |
| 11 | 282 subset job is not a whole group | `utils.R:1180` | site 6 |
| 12 | 282 habitat asks the partition decision | `frs_habitat.R:336` | site 23 |
| 13 | 282 sequential path uses helper | `frs_habitat.R:535` | site 24 |
| 14 | 282 mirai path uses helper | `frs_habitat.R:680` | site 24 |

**Guards from set 1 with no row, that could silently regress:**

- **8b** (`cols_from` arm of the wsg-column guard) — no row at all, and no
  test. Round 3 replaced the one-sided check that row 3 was written against.
- **11b** (`cols_from` half of the `id_segment` `&&`) — row 4 mutates the
  whole `if`, which the "no key at all" test kills; the arm itself is unpinned.
- **22** (`dbBegin`/`dbCommit`/`on.exit` rollback) — no row, but a real test
  (`test-utils.R:661-705`) fails if the transaction goes; round 3's review
  recorded the same.
- **4** (`cols_to = union(…)`), **14** (the wsg statement branch), **20** (the
  `why` branch) — no row; each has a test.

**And the list as committed cannot be swept at all** (finding 1), so the
sweep's recorded evidence — `findings.md`, "Mutation sweep", 10 of 10 against
`f1f649b` — predates rows 6, 7, 11 and 12 and the current code. A measurement
carries the time it was taken.

---

## Findings

- **[bug] `dev/mutation_sweep_sites_persist_282.csv:4` — the site list no
  longer resolves, so the branch's own mutation sweep refuses before it runs a
  single test.** Row 3's pattern is
  `    if (!"watershed_group_code" %in% cols_to) {`. Round 3 replaced that
  one-sided check with the two-sided
  `lacking <- c(to, from)[!c(… cols_to, … cols_from)]` / `if (length(lacking) > 0)`
  at `R/utils.R:1230-1231` and did not update the CSV. `sweep_line()` errors
  when a pattern has fewer matching lines than `occurrence` asks, so the whole
  sweep is REFUSED (exit 2). Measured in a copy:

  ```
  $ Rscript dev/mutation_sweep.R dev/mutation_sweep_sites_persist_282.csv '^(frs_habitat|utils)$'
  copied 189 files to /var/folders/.../mutation_sweep_5487c2d4093
  REFUSED: site '282 wsg column required': pattern '    if (!"watershed_group_code" %in% cols_to) {' matches 0 line(s) of R/utils.R, occurrence 1 asked
  ```

  It fails toward refuse rather than toward clean, which is the right
  direction — but the consequence is that the committed instrument for "prove
  the guard fires" cannot be run on the tree it ships with, and the recorded
  result (10 of 10 against `f1f649b`) covers neither the current code nor the
  four rows added after it. Fix: change row 3's `pattern` to
  `  if (length(lacking) > 0) {` with `within` `.frs_persist_delete_key`
  (note there is a second `if (length(lacking) > 0)`-shaped line nowhere in
  that function, so `occurrence` stays 1 — confirm with the sweep's own
  "sites resolve to:" print), then re-run the sweep and re-record the table.
  - **Rule:** `code-check.md`, "Restore the bug and prove the guard fires";
    also `code-check.md`, "Documentation Staleness".

- **[fragile] `R/utils.R:1231` — the `cols_from` arm round 3 added to the
  watershed-group column guard is caught by no test.** Measured in the copy:
  substituting `"watershed_group_code" %in% cols_from` with `TRUE` leaves the
  filtered suite at 83 tests, 0 failed, 0 errored, 0 skipped. The existing
  test (`test-utils.R:465`) only exercises the `cols_to` side — its
  `cols_from` always carries the column — and the only sweep row for this
  guard is the stale one above. The same arm-level gap exists at
  `R/utils.R:1257` for the `cols_from` half of the `id_segment` `&&`: no test
  passes a `cols_to` that has `id_segment` with a `cols_from` that does not,
  and row 4 mutates the whole `if` rather than the arm. Neither arm is
  reachable through `frs_habitat()` today (the working table always carries
  both columns), so this is unproven coverage rather than a live defect — but
  the guard's stated purpose is "the helper's contract, which has other
  callers ahead of it", and without the arm a future caller gets a `DELETE …
  WHERE watershed_group_code …` whose `INSERT` cannot supply the column.
  One `expect_error()` with the two column lists swapped closes it, plus a
  sweep row per arm.
  - **Rule:** `code-check.md`, "A guard's scope, escape hatches, and
    remedies"; `code-check.md`, "Restore the bug and prove the guard fires".

- **[fragile] `R/utils.R:1371-1379` (and the same sentence in `NEWS.md` and
  `man/frs_habitat.Rd`) — the NULL-key guard's named remedy is circular when
  the key is `watershed_group_code`.** The error says "finish it -- re-run
  every watershed group with `wsg` and no `aoi`, which backfills each group in
  turn". That is correct for the `linear_feature_id` and `id_segment` keys: a
  whole-group run keys on `watershed_group_code`, so it is not blocked by NULL
  `linear_feature_id` rows. It is wrong when the NULL column *is*
  `watershed_group_code` — every whole-group run then hits the same guard, and
  only the other two escapes in the message ("backfill … directly, or drop …
  and re-run") work. It is also a new refusal: before this branch a
  whole-group run on such a target completed. Practically unreachable on
  `fresh.streams`, whose `watershed_group_code` is `NOT NULL`, which is why
  this is `fragile` and not `bug`; but the message is the only place an
  operator will read, and the accepted-tradeoff note covers the guard's
  *scope*, not this remedy. One clause keyed on `key` ("…, or, where the NULL
  column is `watershed_group_code` itself, backfill or drop the table")
  settles it.
  - **Rule:** `code-check.md`, "A guard's scope, escape hatches, and
    remedies".

### Checked and clean (walked, not assumed)

- **`.frs_persist_columns()`'s return shape changed from a character scalar to
  a list.** Grepped every caller in `R/`, `tests/`, `data-raw/`, `dev/`: one
  production call site (`utils.R:1345`) and three test call sites, all
  updated. No stale `sprintf(…, cols, cols, …)` survives.
  (`code-check.md`, "A fix lands in one of two callers that share a harness".)
- **Both `frs_habitat()` paths.** Pinned by parsed body, not by `list.files("R")`
  — which would count zero over zero under `R CMD check`. Same rule.
- **`mockery` is declared in `Suggests:`** and the call is guarded by
  `skip_if_not_installed()`. (`code-check-r.md`, "A `pkg::` call in a test …
  if `pkg` is undeclared".)
- **`withr` is in `Imports:`**, so `data-raw/audit_persist_282.R`'s
  `withr::defer(…, envir = globalenv())` resolves; it is used precisely
  because `on.exit()` at a script's top level never fires, and the script
  loads the source tree with `pkgload::load_all()` rather than the installed
  package. The script sets both `statement_timeout` and `lock_timeout`.
  (`code-check-r.md`, "`on.exit()` at a script's top level never fires",
  "A `data-raw/` script must load the source tree"; `code-check-infra.md`,
  "Set `statement_timeout` + `lock_timeout` on long DB ops".)
- **The audit's `n_missing_*` are `NOT EXISTS` set differences per group, not
  a difference of two differently-filtered counts**, and `groups` drives the
  joins so a group with no FWA rows is kept; NULL-group rows are counted and
  reported separately rather than printed as a row of zeros.
  (`code-check.md`, "One fact derived twice".)
- **Non-ASCII.** The em dashes added to `R/utils.R`, `R/frs_habitat.R` and
  `man/frs_habitat.Rd` are in roxygen comments and in an Rd file where 31 of
  the package's existing Rd files already carry them — pre-existing, not a new
  `R CMD check` condition. `data-raw/` and `dev/` are both in
  `.Rbuildignore`. (`code-check-r.md`, "`deparse()` re-encodes non-ASCII",
  "`R CMD build` ships every top-level directory".)
- **Line length.** No added line in any changed file exceeds the `.lintr`
  limit of 120 (the single >120 line in `test-frs_habitat.R` is at `:494`,
  pre-existing).
- **Concurrency under `workers > 1`.** The new explicit transaction holds only
  `RowExclusiveLock` on the target for the DELETE+INSERT pair; the
  `CREATE TABLE IF NOT EXISTS` and `ALTER TABLE` that take
  `AccessExclusiveLock` are still autocommitted ahead of it, as before. Jobs
  on different groups touch disjoint rows under either key (no
  `linear_feature_id` spans a group), so the pair cannot deadlock between
  workers. (`code-check-infra.md`, "Two-statement DELETE/INSERT into a persist
  table is not atomic" — now one transaction, which is the remedy that rule
  asks for.)
- **The `to_barriers` `blue_line_key` DELETE** (fresh#294) and the
  `to_habitat` / `near_river` loss (fresh#293) are out of scope and filed;
  the parsed-body test pins the `DELETE FROM` count at 2 so a new unscoped
  delete cannot be added silently.
- **Full suite.** Re-run in the copy over `filter = "^(utils|frs_habitat)$"`
  against the live database: **83 tests, 0 failed, 0 errored, 0 skipped**.
  (`code-check-r.md`, "Tests that silently do not run" — `NOT_CRAN=true` was
  set explicitly, and the 0-skip count is the evidence the DB tests ran.)
