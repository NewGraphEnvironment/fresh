# Code-check round 2 — fresh#242 (connectivity passes join a shared habitat table)

Reviewed the **on-disk working tree**, not the diff in the brief. The diff is stale by
one commit: `e6eeb71 Cover the verbose count paths, which no test was executing` added
`verbose =` parameters to `.cwb_run()` / `.dfl_run()` and the
`test_that("the verbose progress lines count this job's groups, not the table's")`
block (`tests/testthat/test-frs_connectivity_wsg.R:398-457`), none of which is in the
diff. Everything below is against `e6eeb71`.

No file under `/Users/airvine/Projects/repo/fresh` was edited. Mutations ran in a
selective copy at
`/private/tmp/claude-501/-Users-airvine-Projects-repo-fresh/41fc5ce3-4d54-49da-ad39-16b1cfd38ce0/scratchpad/fc`
(`R/`, `DESCRIPTION`, `NAMESPACE` only), against the **local Docker fwapg**
(`localhost:5432/fwapg`, `fresh-db`, `Up 4 weeks (healthy)`) using `TEMP` tables only.
The shared instance was never touched and the package test suite was never run.
`cmp` confirmed the copy restored to byte-identity with the real tree after each
mutation, and `git status` is clean.

## Checklist read

| file | bytes | read |
|---|---|---|
| `code-check-infra.md` | 38,115 | **in full** (under the 40,000 threshold) |
| `code-check.md` | 330,698 | `## Mechanisms` **in full, prose and tables**, lines 38-1245 (all 14 H3s). Of `## Rules that stand alone`, `## Security`, `## Spreadsheets and PDFs` I read "Do not edit files a long test run is reading", "An assertion that matches an interpolated value cannot see the claim around it", "Documentation Staleness", "An ordered dispatch…". Not read: the other ~24 H3s under those three sections (config adoption, cold/create path, expiring credentials, artifact-under-test, URL encoding, preview flags, YAML booleans, repo-hosted artifact links, pluralisation markers, the 6 Security rules, the 3 Spreadsheet/PDF rules) — none names a tool, shape or pattern this diff uses. |
| `code-check-r.md` | 178,405 | Read in full: "Tests that silently do not run", "testthat counts an uncaught error under `error`", "A `skip_if_not()` skips only its own block", "`expect_gt()` and friends take no `info`", "`$` on a list partial-matches", "A database driver's value is not a base R type", "A value compared as `::text` in SQL", "`paste()` with a zero-length argument", "Under `R CMD check`, tests run from a temp dir", "`[[` on a named ATOMIC vector", "Postgres row order is never fixed unless the query fixes it" (incl. the correlated-subquery and `CREATE OR REPLACE VIEW` notes under the next heading), "`sprintf(\"%g\")` writes `Inf` and `NA`", "An `information_schema` lookup by the literal table name", "A `function(...)` mock hides arguments", "`expect_message(regexp = \"...$\")`", "`tolerance` in testthat is RELATIVE", "A `pkg::` call in a test". **~95 headings not read** — none names a tool or shape in this diff (arrow/duckdb, `fs::`, `glue()`, xml2, `download.file`, lintr, `.Rbuildignore`, ggplot2, POSIXct, `climr`, `cffr`, `readBin`, pak, `earthdatalogin`, locale collation, encoding, paged.js, `stats::aggregate`/`mad`, `deparse`, …). |
| `code-check-shell.md` | 125,440 | Read: "`git diff a..b` compares TIPS", "A destructive setup and its undo must not share one timeout-able command", "`git checkout <path>` restores from the index", "Put cleanup on the EXIT trap", "A failed `cd` lets every later command run…", "On this Mac `stat` and `date` are GNU", "psql does not interpolate `:'var'`…". **~55 not read** — the diff ships no shell. |
| `code-check-spatial.md` | 155,517 | Read: "A Freshwater Atlas main stem's downstream end…", "FWA `upstream_route_measure` misses the next segment's start", "FWA main flow is not edge type 1000 alone", "A name is not a key: `GNIS_NAME` matches features all over BC", "`sf::st_read()` promotes a mixed POLYGON/MULTIPOLYGON layer". **~75 not read** — no terra, sf, bcdata, GDAL or rasterio in this diff; the geometry work is all PostGIS inside SQL. |

---

## Findings

### 1. `[fragile]` R/utils.R:45-48 — `.frs_wsg_in()`'s inner `watershed_group_code` is unqualified, so the clause silently becomes a no-op

```r
.frs_wsg_in <- function(table) {
  sprintf(" AND watershed_group_code IN (
         SELECT watershed_group_code FROM %s)", table)
}
```

Answering the brief's question 1 directly: at the **outer** level the bare column is
correct and unambiguous at all seven call sites — every one has a single-table
`FROM <habitat>` with no alias and no second table in scope
(`R/frs_cluster.R:152-156`, `175-179`; `R/frs_habitat.R:1371-1374`, `1519-1522`,
`1577-1580`, `1783-1786`, `1960-1963`). I checked every `sprintf()` arity and argument
order in the branch — all 7 counts, both `.frs_distance_filter()` UPDATEs, both
`.frs_connected_waterbody()` UPDATEs, `rearing_spawn_ctes`, `origins_sql`, all three
cluster SQL builders and `.cds_fixture()`'s insert — and every one matches
(details in "Things I checked that are correct" below).

The **inner** one is the problem. Postgres resolves a subquery's unqualified names
inside-out and then outward, so if `table` has no `watershed_group_code` column the
inner `SELECT watershed_group_code` binds to the **outer habitat row**, the subquery
returns that row's own group, the `IN` is always true, and the clause reports the whole
shared table. Measured on the local fwapg:

```
 case     | n
----------+---
 with col | 1      <- 3 habitat rows, 1 in the job's group: correct
 no col   | 3      <- table lacks the column: whole table, no error, no warning
```

That is `code-check-r.md`, "A correlated subquery resolves names from the inside out"
(the rule fresh#259 is cited under), arriving as a guard that fails toward pass.

**Scope, honestly:** no reachable path ships a wrong number, because at every call
site a later statement in the same function joins `s.watershed_group_code`
explicitly and raises first — so a `table` without the column aborts the run rather
than printing a quietly wrong progress line. `frs_cluster()`'s roxygen now states the
precondition but nothing enforces it.

**Remedy, one token, and it fails loudly instead** — measured:

```
SELECT s.watershed_group_code FROM <table> s
#> ERROR:  column s.watershed_group_code does not exist
#> HINT:  Perhaps you meant to reference the column "hab.watershed_group_code".
```

### 2. `[fragile]` R/frs_habitat_classify.R:397-401 — the eighth unscoped count, in the function that owns the shared table

Round 1's finding was "the verbose before/after counts read the whole table", closed at
seven sites. `frs_habitat_classify()`'s own per-species progress line is an eighth, with
the same shape, in the same reachable configuration:

```r
stats <- DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*) FILTER (WHERE accessible)::int AS acc,
          count(*) FILTER (WHERE spawning)::int AS spn,
          count(*) FILTER (WHERE rearing)::int AS rr
   FROM %s WHERE species_code = %s",
  to, .frs_quote_string(sp)))
```

`to` **is** the shared `to_habitat`: `R/frs_habitat.R:479-493` passes `habitat_tbl` as
`to`, and `verbose = verbose && is.null(conn_params)`, which in sequential mode is just
`verbose` (`R/frs_habitat.R:733` calls `.run_job(spec, conn_params = NULL, …)`). Classify
deletes and re-inserts **only this job's groups** (`R/frs_habitat_classify.R:241-249`,
`DELETE … WHERE watershed_group_code = <wsg>` per code), so when group 2 runs, group 1's
rows are already in `to` and its line reports both. `wsg_codes` is already in scope at
line 163, derived from `table` — the fix is appending `.frs_wsg_in(table)` to that one
`WHERE`, exactly as the other seven do.

This is `code-check.md`, "A fix lands in one of two callers that share a harness" — the
brief's question 4. The pass that *reads* the shared table was fixed; the pass that
*writes* it was not, and nothing compares the two. It also makes the round-1 claim
"All seven count sites" an under-count of the class (true of the connectivity passes,
not of the table).

`R/frs_order_child.R:291` has the identical unscoped count beside the single-key UPDATE
round 1 verified and deferred — noted only so the deferred issue carries both lines, not
re-flagged.

### 3. `[bug]` planning/active/findings.md:135-182 — the mutation sweep's "4 defence-in-depth sites" conclusion is wrong; two of them are load-bearing, measured

The brief asks me to say so with a counterexample if either accepted argument is wrong.
Both are, and the code is **fine** — all 19 predicates are present and correct. What is
wrong is the written conclusion that four of them cannot change the answer, because that
is the sentence that licenses a future refactor to drop one while the suite stays green.

#### 3a. `cluster_both`'s `tmp_clusters` join (R/frs_cluster.R:468-469)

The argument rests on the phantom row being a **duplicate** of a row the CTE already
holds ("`ST_ClusterDBSCAN` … insensitive to duplicate geometry", "`DISTINCT ON` picks the
same minimum", "a duplicated `c` row … an UPDATE applies once"). It is not a duplicate
when the other group says `label_cluster = TRUE` on an `id_segment` whose **own** group
says `FALSE`: the CTE then gains a segment the job does not consider rearing, and that
segment can merge clusters and move `cluster_minimums`.

Fixture: one mainstem, `wscode_ltree = '100.100000'` (multi-label, so the empty-`subpath`
boost `findings.md:98-109` sets aside is *not* involved), every cluster minimum ≥ 1000 m
against `confluence_m = 10`, `bridge_distance = 500`:

| id | drm | TEST | OTHR |
|---|---|---|---|
| 1 | 0–1000 | `spawning = TRUE` | — |
| 3 | 1000–2000 | `rearing = FALSE` | `rearing = TRUE` |
| 2 | 2000–3000 | `rearing = TRUE` | — |

```
before : OTHR/3=TRUE  TEST/1=FALSE  TEST/2=TRUE   TEST/3=FALSE
SHIPPED: OTHR/3=TRUE  TEST/1=FALSE  TEST/2=FALSE  TEST/3=FALSE
MUTANT : OTHR/3=TRUE  TEST/1=FALSE  TEST/2=TRUE   TEST/3=FALSE
```

`MUTANT` = line 469 deleted, every other group predicate in the file intact (16 remaining
occurrences). Shipped strips `TEST/2` correctly — its cluster minimum is at drm 2000 and
phase 3's trace reaches spawning 1000 m away, outside the 500 m cap. The mutant pulls
TEST's streams row 3 into `tmp_clusters` via OTHR's habitat row, DBSCAN merges it with
row 2 (adjacent), `cluster_minimums` drops from drm 2000 to drm 1000, the trace now
reaches spawning at 0 m, and `TEST/2` **keeps `rearing = TRUE`**. A wrong answer in the
job's own group, from another group's row, with no `id_segment` duplicate anywhere.

The same thing happens through the `confluence_m` boost as well (`direction = "upstream"`
and `"both"`, single-label wscode, minimum driven below `confluence_m = 10`): shipped
`TEST/2=FALSE`, mutant `TEST/2=TRUE` for both line 225 and line 469. That variant is the
one `findings.md:98-109` argues is a fixture artifact, which is why I built the
multi-label one above.

`cluster_downstream`'s `clustering` join (line 310-311) feeds the identical
`cluster_minimums` → `fwa_downstreamtrace(cm.blue_line_key, cm.downstream_route_measure)`
→ `dist_to_cluster < bridge_distance` chain, so the same mechanism applies; I did not
construct it, because its trace needs real FWA rows. `cluster_upstream`'s (line 224-225)
moves the `FWA_Upstream` origin down the blue line, so more of the network becomes
upstream — reachable by the same reasoning, measured only in the boost form.

#### 3b. `connected_waterbody`'s `spawn_upstream` join (R/frs_habitat.R:1846-1848)

The argument reasons about the wrongly-added stream's **own** row ("a stream it wrongly
adds has `spawning = FALSE` in this group, and the subtractive UPDATE only touches TRUE
rows"). It holds for `lake_adjacent = FALSE`. It fails for `lake_adjacent = TRUE`, which
is the **default** (bcfishpass parity), because `clustered` / `cluster_geoms` /
`valid_clusters` propagate the added stream's lake-adjacency to every other stream in its
cluster:

Fixture anchored on a real `whse_basemapping.fwa_lakes_poly` boundary point,
`waterbody_ha_min = 1`, one mainstem `wscode '100'`, all upstream of a rearing segment:

| id | distance to lake | TEST | OTHR |
|---|---|---|---|
| 1 | 49,999.33 m | `rearing = TRUE` | — |
| 5 | 1,000.50 m | `spawning = TRUE` | — |
| 6 | 0.00 m | `spawning = FALSE` | `spawning = TRUE` |

```
before : OTHR/6=TRUE  TEST/1=FALSE  TEST/5=TRUE   TEST/6=FALSE
SHIPPED: OTHR/6=TRUE  TEST/1=FALSE  TEST/5=FALSE  TEST/6=FALSE
MUTANT : OTHR/6=TRUE  TEST/1=FALSE  TEST/5=TRUE   TEST/6=FALSE
```

`MUTANT` = only `AND hs.watershed_group_code = s3.watershed_group_code` deleted. Shipped
clears `TEST/5` correctly: its cluster is 1,000.5 m from the lake, outside the 2 m
`ST_DWithin` gate. The mutant lets OTHR's row pull TEST's streams row 6 into
`spawn_upstream`; row 6 touches the lake and is adjacent to row 5, so DBSCAN merges them,
`ST_Collect` of the merged cluster is within 2 m, the cluster validates, and `qual_tbl`
gains **id 5** — protecting a TEST row the pass should clear. So the group does not only
"change which habitat row supplies that TRUE"; it changes which *streams* qualify.

#### What follows

Nothing to change in `R/`. Two things to change in the record and the suite:

1. `findings.md`'s "Why the four are unobservable, rather than untested" is false for at
   least two of the four, and its own closing sentence ("the reasoning above is
   contingent on `minpoints = 1` and on `qual_tbl` being a stream keep-list") is weaker
   than the facts: the reasoning is contingent on the other group's flag **duplicating**
   this group's, which is true of every fixture in `test-frs_connectivity_wsg.R` and is
   not a property of the data. Re-state those two rows as load-bearing and uncovered.
2. Two tests close them, and both fixtures are above verbatim: plant the other group's
   `label_cluster` / `spawning` row on an `id_segment` whose **own** group's row is
   `FALSE`, adjacent to and lower than the row under test. That is the one axis every
   existing fixture holds fixed — `code-check.md`, "A fixture that cannot reach the
   failure mode": ask what the fixtures have in common and whether that shared property
   is the thing the bug depends on.

### 4. `[fragile]` tests/testthat/test-frs_cluster.R:72,101 — round 1's mock fix is inert, and the new species-resolution query has no coverage at all

Round 1 changed `grepl("DISTINCT species_code", sql)` to
`grepl("DISTINCT h.species_code", sql, fixed = TRUE)` in both mock tests. Neither test
can observe it: both pass `species = "CO"` and `verbose = FALSE`, and `frs_cluster()`
calls `DBI::dbGetQuery` in exactly two places, one behind `if (is.null(species))` and one
behind `if (verbose)`. So the stub is never reached. Measured in the copy, with the stub
instrumented to count its own calls:

```
pattern=DISTINCT h.species_code  dir=upstream   dbGetQuery calls=0  sql_log=1  pass=TRUE
pattern=DISTINCT h.species_code  dir=downstream dbGetQuery calls=0  sql_log=1  pass=TRUE
pattern=DISTINCT species_code    dir=upstream   dbGetQuery calls=0  sql_log=1  pass=TRUE
pattern=DISTINCT species_code    dir=downstream dbGetQuery calls=0  sql_log=1  pass=TRUE
pattern=NEVER_MATCHES_XYZ        dir=upstream   dbGetQuery calls=0  sql_log=1  pass=TRUE
pattern=NEVER_MATCHES_XYZ        dir=downstream dbGetQuery calls=0  sql_log=1  pass=TRUE
```

A pattern that cannot match anything passes. Reverting the round-1 fix leaves both tests
green.

In the other direction, the query itself is **correct** — I ran it standalone and it
returns exactly the species of the job's groups:

```sql
SELECT DISTINCT h.species_code FROM hab h
 WHERE EXISTS (SELECT 1 FROM str s
               WHERE s.watershed_group_code = h.watershed_group_code);
-- hab = (1,TEST,BT),(1,OTHR,CO),(2,OTHR,SK); str = (1,TEST)  ->  BT
```

But `grep -rn "frs_cluster(" tests/` shows **no test anywhere calls `frs_cluster()` with
`species = NULL`**, so the new `EXISTS` scoping never executes in the suite, and
`frs_cluster()`'s roxygen claim "`species = NULL` resolves only the species present in
`table`'s groups (fresh#242)" is an unexecuted claim
(`code-check.md`, "A guard's scope, escape hatches, and remedies"). It is also the one
site where a silent failure is a **whole pass skipped**: an empty species vector makes
`for (sp in species)` run zero times and `frs_cluster()` return invisibly with every
disconnected cluster intact. One mock test calling `frs_cluster(species = NULL)` with the
stub returning a row for the new pattern, plus one assertion in
`test-frs_connectivity_wsg.R` that `species = NULL` on the two-group fixture resolves to
`"BT"` and not `"CO"`/OTHR's codes, closes it.

---

## Things I checked that are correct

Recorded so the next round does not re-derive them.

- **Predicate completeness (question 1).** Enumerated every `id_segment` join in
  `R/frs_cluster.R` and `R/frs_habitat.R` by grep, then read each one's following line.
  All ten in `frs_cluster.R` (224, 249, 270, 310, 340, 393, 468, 491, 548, 606) carry
  `watershed_group_code`. In `frs_habitat.R`, 1402 (`hab_join`), 1475, 1537, 1543, 1808,
  1840, 1847, 1909 and 1946 carry it; 1441, 1442, 1467 and 1880 are table-to-table or
  temp-to-table joins with no habitat side, and 1913 is the `qual_tbl` `NOT EXISTS` the
  brief accepts. Nothing in `R/frs_cluster.R`, `.frs_distance_filter()` or
  `.frs_connected_waterbody()` still matches a habitat row on `id_segment` alone.
  `.frs_run_connectivity()` reads no habitat rows of its own.
- **`phase1_ids` → `h.<label_connect> IS NOT TRUE` (question 2).** Equivalent, in every
  case I could construct. Every target row is joined to a `tmp_clusters` row and
  `tmp_clusters` is exactly the habitat rows with `label_cluster IS TRUE`, so "phase 1"
  on a target row is exactly `label_connect IS TRUE`; nothing between the old
  `phase1_ids` read and the UPDATE mutated `label_connect`, so the per-row read sees the
  same values the list did. `NULL` → `IS NOT TRUE` is true → unprotected, which is what
  the old `id_segment NOT IN (<ids built from both IS TRUE>)` also did.
  `label_cluster == label_connect` is a no-op both before and after (old: every
  `tmp_clusters` id is in `phase1_ids`; new: `IS NOT TRUE` is false on every target), so
  the degenerate case is preserved rather than changed. Collapsing the two UPDATE
  branches into `valid_clause` is a pure refactor — `""` reproduces the no-`NOT IN`
  branch exactly, and the blank line it leaves is valid SQL.
- **The `.frs_connected_waterbody()` subtractive rewrite (question 3).** For this group's
  rows the `FROM <table> s` join drops nothing: every habitat row in the job's groups has
  exactly one `table` row at the same `(id_segment, watershed_group_code)`, and
  `id_segment` is unique within a working table — confirmed from
  `.frs_add_id_segment()` (`R/utils.R:567`, `id_segment = linear_feature_id`, globally
  unique in FWA) and `R/frs_break.R:699` (`(SELECT max(id_segment) FROM <table>) +
  row_number()`, so a multi-group AOI table is still unique end to end). `NOT IN` →
  `NOT EXISTS` changes behaviour only on a NULL `qual_tbl.id_segment`, which cannot occur
  (every id comes from `table`), and the change is in the safe direction: the old form
  would have cleared nothing at all. `IN` rather than `NOT IN` in `.frs_wsg_in()` is also
  the right way round — a NULL group in `table` leaves the condition NULL (row not
  counted) instead of failing open.
- **The new tests are non-vacuous (question 4, and the brief's round-1 item 4).** I
  hand-evaluated the fixture, the FWA predicates and the printed arithmetic for all four
  scenarios in the verbose test, and each of the seven `.frs_wsg_in()` sites is
  individually detectable: `frs_cluster` unscoped-both prints `1 disconnected removed (4
  rearing remaining)` against the required `(1 rearing remaining`, and unscoped-`n_before`
  alone prints `4 disconnected removed`; `distance_filter` gives `(3 spawning remaining`
  and `3 beyond 1500m removed`; `connected_waterbody` and `bucket_connected` print both
  numbers (`3 -> 2` and `2 -> 1` against the required `2 -> 1` and `1 -> 0`). No single
  site can be neutered without a named assertion going red.
- **`.cds_pick()`'s discovery predicate is sufficient.** `NOT a.wscode_ltree <@
  b.wscode_ltree AND NOT b.wscode_ltree <@ a.wscode_ltree` is exactly the condition
  wanted: a downstream trace only ever reaches segments whose `wscode_ltree` is a prefix
  (ancestor) of the origin's, so if A were on B's downstream path then
  `b.wscode <@ a.wscode` would hold and the pair is excluded. `<@` is reflexive, so two
  blue lines sharing one wscode are excluded too. The `min(watershed_group_code)` +
  `ORDER BY 2, 3 LIMIT 1` pick is deterministic even though a blue line can appear in
  `cand` more than once (one row per `(blk, wscode)`): the duplicate rows name the same
  blue-line pair.
- **`sprintf()` arity and order.** Counted placeholders against arguments for all 7
  count queries, `.frs_cluster_upstream` (12/12), `.frs_cluster_downstream` (13/13),
  `tmp_clusters` (5/5), `sql_phase2` (6/6), `sql_phase3` (7/7), the collapsed final
  UPDATE (6/6), both `.frs_distance_filter()` statements (11/11), `origins_sql` (3/3),
  `rearing_spawn_ctes` (6/6), both `.frs_connected_waterbody()` UPDATEs (4/4 and 5/5),
  `.bkt_fixture()`'s streams insert (17/17) and habitat insert (8/8),
  `.bkt_habitat_add()` (8/8) and `.cds_fixture()`'s insert (3/3, and 14 SELECT columns
  against the 14-column DDL in order). All match.
- **The shared-fixture move is behaviour-preserving for `test-frs_bucket_connected.R`.**
  The three values the old inline `.bkt_fixture()` hardcoded are now `.bkt_seg()`
  defaults with identical values (`gradient = 0.01`, `access = TRUE`,
  `rear = FALSE` → `own && r$rear`), the new `channel_width` / `edge_type` columns are
  appended at the end of both the DDL and the insert, and the file's own explicit
  8-column habitat `INSERT` at line 190-192 still matches the DDL.
- **`.bkt_flags()[["<id>"]]` on a named logical vector** is the loud spelling, not the
  silent one (`code-check-r.md`, "`[[` on a named ATOMIC vector with an absent key is an
  error") — an absent id aborts rather than passing as `NA`.
- **`man/frs_cluster.Rd` is in sync** with the roxygen, and its em dashes are no new
  problem: `DESCRIPTION` declares `Encoding: UTF-8` and 30+ existing `man/*.Rd` already
  carry non-ASCII, including line 124 of this same file.

## Two wrong counts in text (not bugs, but the next reader plans from them)

- `tests/testthat/test-frs_connectivity_wsg.R:403` — "Four call sites, four separate
  `sprintf()` argument lists, so all four are exercised here." There are **seven**
  `.frs_wsg_in()` sites across four functions, and the test does exercise all seven
  (verified above). The sentence understates its own coverage.
- `planning/active/findings.md:170` — the mutation table's last row reads "the four
  verbose count sites (`.frs_wsg_in()` neutered) | yes | … (4 assertions red, one per
  site)". Seven sites, four assertions. Worth fixing in the same edit as finding 3,
  since this table is the branch's durable evidence record.
