# Review — round 3, branch `282-custom-aoi-persist-deletes-other-watersh`

Terminated by enumeration, not by a quiet round. Section 1 names the mechanism,
section 2 walks the candidate set it implies, section 3 lists what the walk turned up.

## Checklist read

| file | read |
|---|---|
| `code-check-infra.md` | in full (41,794 bytes; the index for this file is the whole rule set — every H3 read) |
| `code-check.md` | prose of all 14 H3s under `## Mechanisms`; plus `Documentation Staleness`, `Test the cold/create path of idempotent code, not just the warm no-op`, `An assertion that matches an interpolated value cannot see the claim around it`, `Do not edit files a long test run is reading`, `An ordered dispatch makes severity ordering load-bearing`. ~20 headings under Security / Spreadsheets-and-PDFs not read (no secrets, no spreadsheet, no PDF in this diff). |
| `code-check-r.md` | headings naming DBI/Postgres, testthat, `data-raw/`, roxygen, `R CMD build`/`.Rbuildignore`, `$` partial matching, `paste()`/zero-length, `sprintf` into SQL, `expect_*` traps, `on.exit()` at script top level, `tryCatch` traps, `lintr`/`load_all` resolution, `pkg::` in tests — 31 of ~95. The remainder name arrow/duckdb/terra/ggplot2/readr/climr/earthdatalogin/Rmd machinery this diff does not touch. |
| `code-check-shell.md` | headings naming `git diff a..b` (used to build the branch diff), `grep -c`, `a && b \|\| c`, `cd` guards, heredocs — 6 of ~70. No shell script in the diff. |
| `code-check-spatial.md` | headings naming FWA / PostGIS / `sf::st_as_text` precision / `ST_Intersects` semantics: *FWA main flow is not edge type 1000 alone*, *FWA `upstream_route_measure` misses the next segment's start*, *A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline*, *A name is not a key*, *sf: reproject the polygon to get a lat/lon bbox* — 5 of ~90. No raster, no GDAL CLI, no file-format work in the diff. |

## Mechanism

**A property of the *code* stood in for a property of the *database*.** Every round-1
and round-2 finding is one instance, and each proxy was checkable without a connection,
which is exactly why each survived into a live run:

| round | the property wanted | the predicate shipped | where the proxy lived |
|---|---|---|---|
| 1 | the target holds no row the delete cannot reach | *this call just added the key column* | a fact about the call, not the rows |
| 1 | the job covers every row of the group | `wsg = w` — the group the call **named** | a fact about the argument, not the extraction |
| 1 | delete and insert are one unit of work | *one SQL statement* | a fact about the text, not the engine's command-id semantics |
| 2 | the insert sees the delete's effect | *a CTE is atomic, therefore sequential* | ditto, one level down |
| 2 | `to` and `from` are different relations | `tolower(a) != tolower(b)` | a string, not a `regclass` |
| 2 | the fixture has the target's shape | `CREATE TABLE … AS SELECT * … LIMIT 0` | DDL text, which copies no constraints |
| 2 | `n_missing` is the absent set | difference of two differently-filtered counts | arithmetic over two populations, not a set difference |

The recurring tell is **a predicate whose truth can be decided from the source alone**,
standing in for a fact only Postgres (or only the data) can answer. `code-check.md`
"A proxy is not the property" is the mechanism; "A guard that fails toward pass" and
"A fixture that cannot reach the failure mode" are the two shapes it took.

The round-3 instances below are the same mechanism in two places the fixes did not
reach: a **reference set** chosen from the source (the audit script's `.frs_stream_guards()`,
attributed to a function that applies none) and a **guard whose own proof is a proxy**
(the `regclass` test, pinned only by a mutation list that omits it).

## Enumeration

### 2.1 Guards, `stop()`s and decisions in the code this branch adds or changes

Walked by parsing `R/utils.R` with `parse(keep.source = TRUE)` and recursing each
changed function's body for `stop` / `warning` / `stopifnot` / `.frs_validate_identifier` /
`tryCatch`, rather than from memory. Counts: **7 `stop()`**, **6
`.frs_validate_identifier()` call sites**, **1 `tryCatch` fallback**, **1 non-raising
decision** (`.frs_partition_wsg`) = **15 sites**.

| # | site | property it must enforce | predicate IS the property? | test that fails if removed? |
|---|---|---|---|---|
| 1 | `utils.R:1097-1098` `.frs_validate_identifier(to/from)` in `.frs_persist_columns` | name is a safe identifier | yes | no (own unit tests for the helper only; not swept) |
| 2 | `utils.R:1115-1124` type-mismatch `stop` | a shared column's types agree | yes (`format_type` both sides) | yes — `test-utils.R:195` |
| 3 | `utils.R:1225-1230` wsg branch: `"watershed_group_code" %in% cols_to` | the group delete can address the partition **and** the insert can write it | **proxy** — `cols_to` only; `cols_from` unchecked while the INSERT writes `cols_from` (finding 7; unreachable via `frs_habitat()`) | yes — `test-utils.R:465`; swept ("282 wsg column required") |
| 4 | `utils.R:1239-1244` `in_to != in_from` | both sides carry the key | yes | yes — `test-utils.R:438-456`; swept |
| 5 | `utils.R:1249-1253` neither key present | there is some key | yes | yes — `test-utils.R:457`; swept |
| 6 | `utils.R:1277-1282` `.frs_same_relation(to, from)` | target ≠ source | **proxy**, documented as a pre-filter | yes — `test-utils.R:475-492`; swept ("282 target not source") |
| 7 | `utils.R:1271-1272` `.frs_validate_identifier` in `.frs_persist_delete_sql` | safe identifier | yes | no |
| 8 | `utils.R:1315-1316` `.frs_validate_identifier` in `.frs_persist_streams` | safe identifier | yes | no |
| 9 | **`utils.R:1327-1336` `regclass` equality** | target ≠ source, exactly | **yes — this is the property** | **NO.** No test in `tests/` touches `search_path` (grepped: zero hits), which is the only way two distinct validated strings name one relation. Absent from `dev/mutation_sweep_sites_persist_282.csv`. → finding 2 |
| 10 | `utils.R:1354-1370` NULL-key count | the target holds no row this delete cannot reach **in the partition it addresses** | **measured for the row count** (round-1 fix is correct) but **over-scoped**: the whole table, not the partition → finding 3 | yes — `test-utils.R:511-556` (cold + warm); swept ("282 null-key guard") |
| 11 | `utils.R:1392-1395` `tryCatch(dbBegin)` → `began` | *this failure is the nested-transaction case* | **proxy** — any `dbBegin()` error is read as nesting; a non-nesting failure silently reverts to the autocommitted pair → finding 4 | no; absent from the sweep |
| 12 | `utils.R:1402-1410` `dbBegin`/`dbCommit`/`on.exit` rollback | DELETE+INSERT atomic | yes | yes — `test-utils.R:558-603` (NOT NULL on `tag` forces the insert to fail; the row survives). Absent from the sweep, but a real test exists. |
| 13 | `utils.R:1179-1181` `.frs_partition_wsg(wsg, aoi)` | the job holds every row of the group | **proxy** (`is.null(aoi)`) — sound given `frs_habitat.R:316-323`: `aoi = NULL` ⇒ `job_aoi <- w` ⇒ `frs_network_segment` extracts the whole group with no row filter. Verified by reading all four `.frs_resolve_aoi()` arms and `frs_network_segment.R:132-145`. | yes — `test-utils.R:500`; swept twice |
| 14 | `frs_habitat.R:332` / `:361` `partition_wsg = …` wiring | the persist key reflects the job's coverage | yes | yes — `test-frs_habitat.R:766-772` pins `n_of(".frs_partition_wsg(") == 1`, `spec$partition_wsg` == 2, `wsg_code <- spec$wsg` == 0; swept ("282 habitat asks the partition decision") |
| 15 | `data-raw/audit_persist_282.R:42-48` required-column loop | the two join columns exist | yes | no (data-raw, not tested) |

**Verdict: 15 sites walked. 9 are the property; 5 are proxies (3, 6, 11, 13 and 10's
scope); 1 (#9) is the property but has no proof.** Sites 3, 11 and 10's scope are new
findings; 6 and 13 are documented and sound.

### 2.2 Test fixtures this branch adds, and what each can structurally reach

| fixture | shape | can reach | **cannot** reach |
|---|---|---|---|
| `test-utils.R:511` "refuses a target whose key it just added" | `dst(id_segment integer)` + 1 row; `src(id_segment, linear_feature_id)` | NULL-key guard on first **and** warm run (the round-1 bug) | unique/PK indexes, NOT NULL, defaults, generated columns, triggers, RLS, partitioning, geometry type/SRID, FKs, the `watershed_group_code` key path |
| `test-utils.R:558` "replaces its partition atomically" | `dst` + **UNIQUE INDEX** + `tag text NOT NULL`; `src.tag = NULL` | transaction rollback; the atomicity claim | geometry type/SRID typmod mismatch, generated columns, triggers, deferred constraints, exclusion constraints, partitioned targets, FKs; a failure *between* the two statements (it forces a failure *at* the insert) |
| `test-utils.R:605` "re-runs over a target with a unique index" | `dst` + **UNIQUE INDEX**; 3 runs each key | the round-2 duplicate-key bug, under **both** keys | same list as above; also cannot see a concurrent second writer |
| `test-utils.R:648` "allows an empty target gaining the key" | `dst(id_segment)` 0 rows | the cold path (no false positive) | anything constraint-shaped |
| `test-utils.R:678` "chooser and statement never disagree" | pure, 6 column sets | chooser/builder divergence over the full key lattice | anything needing a connection; a non-deterministic chooser |
| `test-utils.R:716` "returns the three keys it should" | pure | the three return values | — |
| `test-frs_habitat.R:646` "custom-AOI persist keeps another group's row" | real FWA ltree AOI; `tgt` created by `.frs_persist_streams`'s own CTAS | the #282 cross-group deletion, end to end, with a live-collision pre-assertion | **no constraints at all** (CTAS copies none) — which is precisely why the round-2 duplicate-key bug was invisible here; also no `wsg` job into the same table, no `workers > 1`, no `wsg` + `aoi` run |
| `test-frs_habitat.R:709` "both paths persist through the one helper" | parsed-body enumeration | wiring/text regressions in both branches, including the mirai closure, with no DB | whether either path **executes**; a behaviour change that keeps the text |

**Verdict: 8 fixtures. 3 carry a unique index (the round-2 gap is closed for the unit
helper). 0 carry a geometry column, a generated column, a trigger, RLS, partitioning or
an FK; 0 execute the mirai path; 0 run `wsg` + `aoi` end to end.** The two structural
gaps that matter are both on the integration fixture (`tgt` has no constraints, so it
still cannot tell a correct overwrite from a CTE one) and the mirai path, which is pinned
by text rather than execution. The text pin is defensible here — one call site per path,
identical arguments, one helper — so I am not reporting it.

### 2.3 Prose claims asserting a quantity, a universal, or a behaviour

| # | claim | where | verdict |
|---|---|---|---|
| 1 | "An AOI is a row predicate: it selects whole FWA segments and **never** truncates one at the AOI boundary" | `NEWS.md:7`, `frs_habitat.R:59-60`, `utils.R:1199-1203` | **supported.** All four `.frs_resolve_aoi()` arms are `&&` or `ST_Intersects` (`utils.R:950-1005`); `frs_extract()` is `CREATE TABLE … AS SELECT … WHERE` with no geometry operation (`frs_extract.R:106-109`); `frs_network_segment`'s two character arms pass `where =` (`frs_network_segment.R:132-145`). No clip anywhere on the path. |
| 2 | "**No** `linear_feature_id` spans a watershed group — 0, measured province-wide" | `NEWS.md:7`, `utils.R:1206-1208` | **supported, and stronger than claimed.** `linear_feature_id` is the PRIMARY KEY of `whse_basemapping.fwa_stream_networks_sp` (measured: `pg_index` shows one unique index, `indisprimary`, on that column alone), so one row ⇒ one group structurally, not just empirically. |
| 3 | "`fresh.streams` has `streams_pkey` on `(id_segment, watershed_group_code)`, and so does **every** sibling schema's `streams`" | `utils.R:1382-1384` | **NOT supported as written.** Measured on the shared instance: the only other relation named `streams` is `bcfishpass.streams`, whose sole unique index is `bcfishpass.streams_pkey` on `segmented_stream_id`. `fresh.streams` is not present on that instance so the first half is unverified here (it is consistent with `CLAUDE.md`). The fix does not rest on the claim. → finding 6 |
| 4 | "The overwrite is **one statement** rather than a DELETE and an INSERT autocommitted separately" | `NEWS.md:16` | **NOT supported.** Shipped code is two statements in one transaction (`utils.R:1392-1410`), and `utils.R:1378` says "**NOT** one statement" in the same breath. Stale round-1 text. → finding 5 |
| 5 | "`data-raw/audit_persist_282.R` reports … the FWA segments **under `frs_extract()`'s own guards**" | `NEWS.md:9`, `audit_persist_282.R:11` | **NOT supported.** `frs_extract()` applies no guards; `.frs_stream_guards()` is called only from `frs_network.R`, `frs_network_upstream.R`, `frs_network_downstream.R`, `frs_network_prune.R`, `frs_stream_fetch.R`. → finding 1 |
| 6 | "`wsg` **and** `aoi` together, which narrows the job to a subset of the group" | `frs_habitat.R:58-59` | **NOT supported for an `sf`/list `aoi`.** `frs_habitat.R:323` sets `job_aoi <- aoi`, replacing the group predicate, so the job can cover ground outside the group entirely — which `.frs_partition_wsg()`'s own roxygen (`utils.R:1174-1177`) and `NEWS.md:9` both state correctly. Doc only; the key is right either way. → finding 8 |
| 7 | "re-run the affected group with `wsg` **and no `aoi`**, the whole-group overwrite being self-healing" | `NEWS.md:9`, `frs_habitat.R:71-72` | **supported** for the group re-run itself (the group DELETE + full re-extract rewrites it). **Incomplete**: on a legacy table the first such run ALTERs `linear_feature_id` on and backfills only its own group, after which every custom-AOI run is blocked by the other groups' NULLs. → finding 3(b) |
| 8 | "Each run overwrites its own partition … in one transaction, so a run that fails leaves the partition as it was" | `frs_habitat.R:54-56` | **supported with one caveat**: true whenever `dbBegin()` succeeds; a silently-swallowed `dbBegin()` failure drops the guarantee (finding 4). The `ALTER TABLE ADD COLUMN` in `.frs_persist_columns()` is also outside the transaction, but it is additive and does not change the partition. |
| 9 | "It also refuses a target holding rows whose key is NULL, **for whichever of the three keys** the run uses" | `NEWS.md:15` | **supported** — the guard reads the key from the one chooser (`utils.R:1353`); `test-utils.R:678` asserts the chooser/statement agreement over all six column sets that reach a key. |
| 10 | "the copies had drifted (one quoted `wsg_code` through `.frs_quote_string()`, the other interpolated `'%s'` raw)" | `utils.R:1307-1310`, `NEWS.md:14` | **supported** by the diff (`frs_habitat.R` removed lines: `"… = %s", .frs_quote_string(wsg_code)` vs `"… = '%s'", wsg_code`). |
| 11 | "of one run's 275 derived `id_segment` values, **81** each equalled a real `linear_feature_id` in the run's own watershed group, and **none** fell in another group" | `NEWS.md:8`, `utils.R:1216-1219` | **unverified here** (needs the measured AOI run). Internally consistent and cited to `research/id_segment_identity.md`. |
| 12 | "**259** blue lines span more than one watershed group" (#294) | `NEWS.md:23` | **unverified here**; out of scope by the stated tradeoffs. |
| 13 | "there is no Postgres service in `.github/workflows/`, so these are the only proof … that runs on CI" | `test-utils.R:394-396`, `utils.R:1155-1157` | **supported** — three workflow files, none with a `services:` block or a postgres image. |
| 14 | "Every `DELETE` left in the body is the `to_barriers` `blue_line_key` one" | `test-frs_habitat.R:727-731` | **supported** and mechanically pinned: the test asserts `n_of("DELETE FROM") == n_of("blue_line_key IN") == 2`. |

**Verdict: 14 claims walked. 8 supported (2 of them more strongly than stated), 1
supported-with-caveat, 1 supported-but-incomplete, 2 unverified-here, 4 NOT supported
(#3, #4, #5, #6).** All four unsupported claims are prose; none changes the shipped
delete key.

### 2.4 Suite state

Ran the `utils|frs_habitat` filter against a live Postgres in a copied tree
(`DESCRIPTION NAMESPACE .Rbuildignore R man tests inst` into the scratchpad, not the
repo): **160 tests, 0 failed, 0 errors, 0 skipped.** So the DB fixtures above actually
executed rather than skipping.

## Findings

- **[bug]** `data-raw/audit_persist_282.R:11,50,61-85` (and `NEWS.md:9`) — the audit's
  reference set is `.frs_stream_guards()`-filtered FWA, attributed in both the header
  comment and the SQL to "`frs_extract()`'s own guards". **`frs_extract()` applies no
  guards** (`R/frs_extract.R:74-113`; `.frs_stream_guards()` is referenced only by
  `frs_network.R`, `frs_network_upstream.R`, `frs_network_downstream.R`,
  `frs_network_prune.R`, `frs_stream_fetch.R`). A `frs_habitat()` run therefore writes
  the unguarded rows into `to_streams` while the audit's `n_fwa_segments` and `n_missing`
  exclude them. Measured on one group: `watershed_group_code = 'BULK'` has 32,472 FWA
  rows, **2,426 of them (7.5%) fail the guards** (`localcode_ltree IS NULL OR
  wscode_ltree <@ '999'`). Two consequences, both in the wrong direction for a damage
  audit: a partition that lost only unguarded rows reports `n_missing = 0`, and a
  *healthy* partition reports `n_in_table > n_fwa_segments`, which reads as a different
  anomaly. Secondary: `groups` is `SELECT DISTINCT watershed_group_code`, so a NULL-group
  partition enters the list but `LEFT JOIN … USING (wsg)` never matches it, and it prints
  `0 / 0 / 0`. Fix: drop the guard clause from the `fwa` and `missing` CTEs (so the
  reference set is what `frs_extract()` actually selects), or apply the guards in
  `frs_extract()` and say so — but the two must be the same population.
  - **Rule:** code-check.md "A proxy is not the property"

- **[fragile]** `R/utils.R:1327-1336` — the exact `regclass` same-relation test, which is
  round 2's fix for the proxy at `:1277`, **has no test that can fail if it is removed**,
  and it is not one of the 12 sites in `dev/mutation_sweep_sites_persist_282.csv`. Every
  same-relation test in the suite goes through `.frs_persist_delete_sql()`'s string
  compare (`test-utils.R:475-492`); nothing under `tests/` touches `search_path`
  (grepped: zero hits), which is the only way two distinct validated strings resolve to
  one relation. This is the live half of the pair: `to_streams` is caller-supplied and may
  be unqualified, while `from` is always the qualified `working.streams_<label>`. Add a
  fixture that sets `search_path` and passes an unqualified `to`, and a sweep row for the
  `if (length(same) == 1 && !is.na(same) && same)` line.
  - **Rule:** code-check.md "Restore the bug and prove the guard fires"

- **[fragile]** `R/utils.R:1354-1370` — the NULL-key guard is scoped to the **whole
  target** rather than to the partition the delete addresses, so it refuses correct runs.
  Two reachable cases. (a) With the `watershed_group_code` key, any row anywhere in `to`
  carrying a NULL group blocks a `wsg` job whose own rows all carry a group and so can
  never be the unreachable ones. (b) On a pre-0.53.0 table the repair path self-blocks:
  the first `wsg` run ALTERs `linear_feature_id` onto `to` (`.frs_persist_columns()`,
  outside any transaction, so it persists through the raise) and backfills only its own
  group, after which **every** custom-AOI run errors on the other groups' NULLs until all
  of them have been re-run — which the repair instruction at `NEWS.md:9` and
  `frs_habitat.R:71-72` does not mention. The remedy the error offers is "drop `<to>` and
  re-run". Scope the count to the delete's own predicate (`WHERE watershed_group_code =
  '<code>' AND <key> IS NULL` for the group key; the AOI's `linear_feature_id` set for the
  parent-segment key), or state the all-groups prerequisite in the repair note.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[fragile]** `R/utils.R:1392-1395` — `began <- tryCatch({DBI::dbBegin(conn); TRUE},
  error = function(e) FALSE)` reads **every** `dbBegin()` failure as the nested-transaction
  case the comment above it names. Any other failure silently reverts to the
  DELETE-and-INSERT-autocommitted-separately form this block exists to replace, with no
  message and no test — the same shape as the round-1 one-shot guard, inferring a
  condition from a failure instead of measuring it. Decide it rather than inferring it:
  check the connection's transaction state first, or match the condition message, or use
  `DBI::dbWithTransaction()` and let a genuine failure propagate.
  - **Rule:** code-check.md "A guard that fails toward pass"

- **[fragile]** `NEWS.md:16` — "The overwrite is **one statement** rather than a DELETE and
  an INSERT autocommitted separately" describes the data-modifying CTE that round 1 shipped
  and round 2 removed. The code is two statements in one transaction, and `R/utils.R:1378`
  says "**NOT** one statement" with the measured reason. The user-facing changelog now
  records the design the branch rejected, which is an invitation to reinstate it; the
  consequence the sentence claims is correct, only the mechanism is wrong. Reword to "one
  transaction".
  - **Rule:** code-check.md "Documentation Staleness"

- **[fragile]** `R/utils.R:1382-1384` — "and so does **every** sibling schema's `streams`".
  Measured: on the shared instance the only other relation named `streams` is
  `bcfishpass.streams`, whose sole unique index is on `segmented_stream_id`, not
  `(id_segment, watershed_group_code)`. The two-statement form is correct whatever the
  index covers, so the comment's reasoning survives without the universal — drop it or
  name the tables it was measured on.
  - **Rule:** none

- **[fragile]** `R/utils.R:1225-1230` — the whole-group branch of `.frs_persist_delete_key()`
  checks `"watershed_group_code" %in% cols_to` but not `cols_from`, while the INSERT at
  `:1407` writes only `cols_from`. A `from` without the column would insert NULL-group rows
  that the next run's delete cannot reach, and the NULL guard runs *before* the insert so
  it cannot see them — run N writes them, run N+1 errors permanently. The
  `linear_feature_id` branch at `:1236-1246` checks both sides for exactly this reason, so
  the asymmetry is unintended. **Not reachable through `frs_habitat()` today** (every
  `frs_extract()` of `fwa_stream_networks_sp` carries the column, and `source =` is not
  exposed), so this is about the helper's stated contract — "the single place the key is
  decided", for any network — rather than current behaviour.
  - **Rule:** code-check.md "A proxy is not the property"

- **[fragile]** `R/frs_habitat.R:58-59` — "`wsg` **and** `aoi` together, which narrows the
  job to a subset of the group" is false for an `sf` or list `aoi`: `frs_habitat.R:323`
  sets `job_aoi <- aoi`, replacing the group predicate, so the job can cover ground
  outside the group entirely. `.frs_partition_wsg()`'s roxygen (`utils.R:1174-1177`) and
  `NEWS.md:9` both say this correctly; only the user-facing `@param` does not. The key
  chosen (`linear_feature_id`) is right either way.
  - **Rule:** none

### Checked and clean

Not reported, having been checked and found sound: the `linear_feature_id` delete key
itself (FWA PK, verified); `.frs_partition_wsg()`'s proxy (sound given
`frs_network_segment`'s dispatch, all four `.frs_resolve_aoi()` arms read); the
chooser/builder double derivation (pure function, same arguments, pinned over the full
key lattice by `test-utils.R:678`); `on.exit(..., add = TRUE)` lazy evaluation of
`committed`; `NULL` elements surviving `list()` and mirai serialisation for
`spec$partition_wsg` (no `$` partial-match hazard — the key is exact and no sibling shares
its prefix); `sprintf("%s", DBI::dbQuoteIdentifier(...))` (DBI's `SQL` class `contains =
"character"`); `IN (SELECT …)` with NULLs in the subquery (cannot over-delete);
`withr` declared in `Imports`; `pkgload::load_all()` in the `data-raw/` script (loads the
source tree, per `code-check-r.md`); `withr::defer(envir = globalenv())` firing at
`Rscript` exit including after `stop()`; `expect_no_error()` already in use pre-branch;
`expect_match`/`expect_false` accepting `info`; `dev/` and `data-raw/` both in
`.Rbuildignore`; `deparse(body())` keeping string literals whole, so the body-text counts
are sound.
