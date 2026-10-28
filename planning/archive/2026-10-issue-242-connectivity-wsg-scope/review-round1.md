# Code check — fresh#242, round 1

Branch `242-connectivity-passes-join-a-shared-habita`, base `c408b468`, HEAD `9cc4c15`.
Reviewed 2026-10-28. No file under the repo was edited; mutation work was done in
`$SCRATCH/mut` and `$SCRATCH/mut2` copies of `R/`, `man/`, `tests/`, `DESCRIPTION`,
`NAMESPACE`, `inst/`.

## Checklist read

- `code-check-infra.md` (38,115 B) — **in full**.
- `code-check.md` (330,698 B) — the prose of **every** H3 under `## Mechanisms`
  (14 of 14), `|` table rows skipped. Plus, from `## Rules that stand alone`:
  "Do not edit files a long test run is reading", "An ordered dispatch makes severity
  ordering load-bearing", "An assertion that matches an interpolated value cannot see
  the claim around it". Not read: the Security, Spreadsheets-and-PDF and remaining
  stand-alone headings (~11), none of which the diff touches (no secrets, no CI, no
  spreadsheets, no URLs, no YAML).
- `code-check-r.md` (178,405 B) — read: "Postgres row order is never fixed unless the
  query fixes it", "A database driver's value is not a base R type", "A value compared
  as `::text` in SQL has PostgreSQL's spelling", "An `information_schema` lookup by the
  literal table name", "`sprintf(\"%g\", x)` writes `Inf` and `NA` into SQL as bare
  words", "`[[` on a named ATOMIC vector with an absent key is an error", "`paste()`
  with a zero-length argument returns length ONE", "Tests that silently do not run",
  "testthat counts an uncaught error under `error`", "A `skip_if_not()` skips only its
  own `test_that()` block", "Under `R CMD check`, tests run from a temp dir against the
  INSTALLED package", "A `pkg::` call in a test … if `pkg` is undeclared", "Inserting a
  helper between a roxygen block and its function rebinds `@export`", "Rscript reads a
  script as it runs". Not read: ~75 headings on arrow/duckdb, readr/CSV, terra-adjacent
  R, ggplot2, climr, earthdatalogin, pak, Rd/vignette mechanics, date-time parsing —
  none appear in the diff.
- `code-check-spatial.md` (155,517 B) — read: "A Freshwater Atlas main stem's downstream
  end lies on the receiving river's centreline", "FWA `upstream_route_measure` misses the
  next segment's start", "FWA main flow is not edge type 1000 alone", "A name is not a
  key: `GNIS_NAME` matches features all over BC". Not read: ~95 headings on terra, GDAL,
  STAC, lidR, gdalcubes, bcdata, KML/COG/GeoPackage — the diff contains no raster, no
  file I/O and no sf call.
- `code-check-shell.md` (125,440 B) — read: "`git diff a..b` compares TIPS". Not read:
  ~60 headings; the diff contains no shell, no `gh`, no `sed`/`awk`, no S3.

## Findings

### 1. **[bug]** `R/frs_order_child.R:271-279` — the same defect survives in an exported sibling, and it writes *additively*

The branch fixes every habitat↔streams join in `frs_cluster()`,
`.frs_distance_filter()` and `.frs_connected_waterbody()`. `frs_order_child()` is a
fourth exported function over the same two tables and its UPDATE still joins on
`id_segment` alone:

```r
     UPDATE %s h
     SET %s = TRUE
     FROM s
     WHERE h.id_segment = s.id_segment
       AND h.species_code = %s
       AND h.accessible = TRUE
```

Its own `@examples` (lines 180-199) run it against the **persisted** multi-group tables
(`"fresh.streams"`, `"fresh.streams_habitat"`), which is exactly the population
`CLAUDE.md` says must always be joined on `(id_segment, watershed_group_code)`
(fresh#218). It is not called from inside the package, so nothing in the test suite
reaches the SQL, and it is not on the brief's deliberately-left list — that list names
only the `frs_habitat.R` persist DELETE and `frs_habitat_overlay()`.

Measured, pg_temp fixture, one streams row in group `TEST` and two habitat rows sharing
`id_segment = 7`:

```
                   before            after frs_order_child(species = "BT")
  TEST  7  rearing FALSE      TEST  7  rearing TRUE
  OTHR  7  rearing FALSE      OTHR  7  rearing TRUE     <- streams table holds no OTHR row
```

Worth separating from the subtractive passes: this one sets `TRUE`, so the failure is a
silently **inflated** habitat set in a group the job never segmented, which no
"disconnected removed" count will ever show. `code-check.md`, "A fix lands in one of two
callers that share a harness" — the count is the signal; this is the fourth member of the
pair. Fix is the one line the rest of the branch adds, plus a group-matched test.

### 2. **[fragile]** `R/frs_cluster.R:18-19` and `R/frs_habitat.R:1732-1735` — the new roxygen states a universal the same functions break, and the per-job count it describes is wrong on a shared table

Two new doc sentences land in this diff:

- `frs_cluster()` `@param habitat`: "A shared habitat table holding other groups' rows is
  therefore safe — **they are never read or cleared**".
- `.frs_connected_waterbody()`: "every join matches `watershed_group_code` too … so other
  groups are **never read or written**".

Both are false for the functions' own `verbose` reporting, which filters on
`species_code` only (`R/frs_cluster.R:152-156`, `174-177`; `R/frs_habitat.R:1782-1784`,
`1958-1960`). I am *not* re-flagging the decision to leave the counts unscoped. The
reviewable defects are (a) an exported `@param` asserting a universal that the function
violates twenty lines below, and (b) the number the serial path actually prints.

`frs_habitat()` forwards `verbose` to `.frs_run_connectivity()` on the non-mirai path
(`R/frs_habitat.R:498-500`, `verbose = verbose && is.null(conn_params)`), so a
`workers = 1L` multi-WSG run with a shared `to_habitat` prints one line per job whose
number is the whole table's. Measured — four TEST segments, three unrelated `OTHR`
rearing rows, `frs_cluster(direction = "upstream", verbose = TRUE)`:

```
  BT: 2 disconnected removed (4 rearing remaining, 0s)
TEST group rearing remaining (truth): 1
```

The line names the species and reads as the job's; the figure is 4 against 1. Either
scope the three count queries to the groups in `table` (the same `EXISTS` the species
resolver at `R/frs_cluster.R:138-145` now uses) or drop the "never read" clause from both
doc blocks. `.frs_bucket_connected()`'s pre-existing "so they are never read or cleared"
(`R/frs_habitat.R:1346-1347`) and `count_bucket()` (`1370-1374`) are the same pair, from
#240. `.frs_distance_filter()`'s new sentence ("never cleared and never satisfy the
connection test") is accurate as written.

### 3. **[fragile]** `tests/testthat/test-frs_connectivity_wsg.R:281-283, 310-319` — the downstream fixture's population is a `LIMIT 1` with no `ORDER BY`, and its two selections do not agree

`.cds_pick()` chooses the watershed group it builds the whole fixture from with:

```sql
WITH g AS (
  SELECT watershed_group_code AS w
  FROM whse_basemapping.fwa_stream_networks_sp LIMIT 1),
```

The repo's own convention is explicit here (`code-check-r.md`, "Postgres row order is
never fixed unless the query fixes it"): rows come back in physical order, and
`synchronize_seqscans` is `on` on this server. Measured today it is stable — 15/15
`TSEA`, plan `Limit → Seq Scan` with no parallel workers — but the heap order moves with
any write, `VACUUM FULL`, `CLUSTER` or restore, and a different database picks a different
group. The consequence is not a wrong assertion, it is that a failure cannot be re-run
against the pair that produced it; the `skip_if()` and the "stripped" assertions only
catch the pair being unusable, never the pair having changed. Every one of five sampled
groups has 3·10^5–1.9·10^6 qualifying pairs, so `ORDER BY watershed_group_code LIMIT 1`
costs nothing and pins it.

Second half, same function: `cand` qualifies a blue line under
`watershed_group_code = g.w AND blue_line_key = watershed_key` and
`HAVING count(*) BETWEEN 3 AND 8`, but `.cds_fixture()`'s insert drops both filters —

```sql
    FROM whse_basemapping.fwa_stream_networks_sp
    WHERE blue_line_key IN (%d, %d)
```

— so a blue line extending into a second watershed group contributes extra segments,
every one of them labelled `'TEST'`, and `a`/`b` no longer hold the 3–8 rows the `HAVING`
measured. Not reachable for the currently-picked pair (both blue lines sit in one group
with exactly 3 rows each, measured), but it is one population stated twice with different
predicates (`code-check.md`, "One fact derived twice"). Carry the group and the
mainstem predicate into the insert.

## Answers to the four questions

**1. Is the predicate set complete?** Yes. Every site where a habitat row is matched,
read or written in the three functions now carries the group. Enumerated by grepping
every `id_segment` equality in `R/` and reading each:

| site | form | group matched |
|---|---|---|
| `frs_cluster.R:138-145` | species resolver | `EXISTS` on `watershed_group_code` |
| `frs_cluster.R:222`, `308`, `466` | `clustering`/`tmp_clusters` build | yes |
| `frs_cluster.R:247`, `489` | `valid_clusters` h2↔st (phase 2) | yes |
| `frs_cluster.R:338` | `has_connect` EXISTS (downstream) | yes |
| `frs_cluster.R:546` | phase-3 `LEFT JOIN` | yes |
| `frs_cluster.R:268`, `391`, `604` | the three UPDATEs | yes |
| `frs_habitat.R:1536`, `1542` | `.frs_distance_filter()` UPDATE + `NOT EXISTS` | yes |
| `frs_habitat.R:1806`, `1838`, `1845` | origins, `rearing_segs`, `spawn_upstream` | yes |
| `frs_habitat.R:1907`, `1944` | subtractive + additive UPDATEs | yes |

The sites that legitimately carry `id_segment` alone all join a temp table to `table`,
never to `habitat`: `frs_habitat.R:1440`, `1441`, `1466`, `1878`, `1911`, `1820`. That is
sound, and I confirmed the premise it rests on rather than taking it from the brief:
`.frs_add_id_segment()` seeds `id_segment` from the globally unique
`linear_feature_id` (`R/utils.R:551-552`) and `frs_break_apply()` extends it with
`(SELECT max(id_segment) FROM <table>) + row_number()` (`R/frs_break.R:695-701`), so
`id_segment` is unique within one working table however many groups it spans.

Outside the three functions: `frs_order_child.R:274` is finding 1;
`frs_habitat_overlay.R:251` and the `frs_habitat.R` persist DELETE are the brief's
deliberately-left pair; `frs_habitat_classify.R:383` joins the per-threshold access temp
table, which is built from `table`.

**2. The `phase1_ids` removal — equivalent?** Yes, for a single-group run, and the
replacement is strictly correct where the old form was not. The equivalence argument the
comment gives holds: every row the final UPDATE targets is joined to a `tmp_clusters`
row, `tmp_clusters` is built from exactly the habitat rows with `label_cluster IS TRUE`
for this species, and the join pins `h` to that same row on
`(id_segment, watershed_group_code, species_code)` — so on a target row
`label_cluster IS TRUE` holds by construction and "phase 1" reduces to
`label_connect IS TRUE`. The three edge cases asked about:

- **`label_cluster == label_connect`.** Both forms become no-ops. Old: `phase1_ids` is
  every clustered id, so `NOT IN` excludes all of them. New: every target row has the
  column TRUE, so `IS NOT TRUE` excludes all of them. Same.
- **NULL vs FALSE.** `IS NOT TRUE` is the right choice and it is pinned. Old `phase1_ids`
  required `label_connect IS TRUE`, so a NULL was never protected; `= FALSE` would have
  started protecting it. Mutated `AND h.%s IS NOT TRUE` → `AND h.%s = FALSE` in a copy:
  `test-frs_connectivity_wsg.R:148` (`own[["6"]]`) goes red, 1/23 assertions failing.
- **The two collapsed branches.** `valid_clause` is `""` when `all_valid` is empty, which
  reproduces the old no-cluster-filter branch exactly; the statement parses (`… IS NOT
  TRUE` followed by empty) and I exercised it.

Nothing writes `label_connect` between the `tmp_clusters` build and the UPDATE, so
reading it at UPDATE time rather than before the build is the same read. And in
`.frs_run_connectivity()` the rearing pass completes before the spawning pass starts, so
the cross-pass ordering is unchanged too.

**3. The `.frs_connected_waterbody()` subtractive rewrite — does it change which rows of
this group get cleared?** No, in any case that can arise. The one behavioural difference
is that the new form cannot clear a habitat row for one of `table`'s groups whose
`id_segment` is absent from `table`. That set is empty: `frs_habitat_classify()` DELETEs
the group's rows and re-INSERTs them straight from `table`
(`R/frs_habitat_classify.R:372-386`), and `frs_habitat()` passes the same `streams_tbl`
to classify and to `.frs_run_connectivity()` (`R/frs_habitat.R:486-500`, `654-662`). The
`NOT EXISTS` on `id_segment` alone is exact, as the comment says, because `h` is pinned
to a row of `table` and `id_segment` is unique there (premise checked above); and it is a
small improvement on `NOT IN`, which fails open on a NULL in the subquery. Worth noting
as a latent dependency rather than a defect: the habitat DDL
(`R/frs_habitat_classify.R:228-238`) declares no key, so
`(id_segment, watershed_group_code, species_code)` uniqueness rests on `overwrite = TRUE`
being the default (line 134) and on every in-package call passing it. A direct
`frs_habitat_classify(overwrite = FALSE)` into a shared `to_habitat` would duplicate rows
within one group and reinstate the phase-3 trace-distance double-counting this branch
removed. A unique index would make that invariant mechanical.

**4. The new tests — can each one fail?** Yes. Every `test_that()` block has at least one
assertion that goes red against the pre-branch files. I replayed all nine blocks'
assertions as a standalone script (no testthat, so nothing was written into `tests/`)
against the branch and against `git show c408b468:R/frs_cluster.R` +
`R/frs_habitat.R` in a copy:

```
branch:      FAILS 0 / 23
pre-branch:  FAILS 9 / 23   (cwb1 OTHR3, cwb2 own4, cwb3 OTHR2, both1 own3,
                             both2 own4, up own3, up OTHR5, dfl1 OTHR3, dfl2 own3)
downstream (run separately, real FWA rows):
  pre-branch test 1: OTHR b2 = FALSE (want TRUE)   -> red
  pre-branch test 2: own  b2 = TRUE  (want FALSE)  -> red
```

Two further mutants, to check the assertions that pass pre-branch are not decoration:
removing the phase-1 clause entirely reddens `both1 own5`; `IS NOT TRUE` → `= FALSE`
reddens `both1 own6`. So `expect_true(own[["5"]])` and `expect_false(own[["6"]])` are
both load-bearing.

**On the discovery predicate** (`NOT a.wscode_ltree <@ b.wscode_ltree AND NOT b <@ a`):
sufficient. `<@` is "is a descendant of, equality included", so the pair excludes both
ancestor relations in both directions. A downstream path in the FWA consists of segments
on the same `wscode_ltree` at a lower measure plus segments on **ancestor** wscodes, and
`.frs_cluster_downstream()` restricts the trace further to
`t.blue_line_key = t.watershed_key`; so neither stream can appear on the other's
downstream path. For the pair this database picks (`359074770` wscode
`200.692231.270936.364064.694721.724921`, `359107149` wscode
`200.692231.270936.406179.120252.246052`) the codes diverge at label 4, i.e. siblings
under one sub-basin, which is the case the comment says is fine. The `expect_false`
assertions are the backstop if a database ever yields a related pair, and they do fire
(verified against pre-branch above). Residual risk is finding 3, which is about *which*
pair, not about the predicate.

## Notes — not findings

- `tests/testthat/test-frs_connectivity_wsg.R:149`, `expect_true(.bkt_flags(…, wsg =
  "OTHR")[["3"]])`, **passes against the pre-branch code** (measured). The pre-fix bug
  validated cluster C via `OTHR`'s spawning row, so the strip never reached `OTHR`'s own
  row; only `own[["3"]]` on line 146 is decisive in that block. Every other
  "other group untouched" assertion in the file does fail pre-branch. The file's header
  comment ("Each test asserts in both directions") is true of the file, not of that line.
- `man/frs_cluster.Rd` is **modified and uncommitted**, so `HEAD`'s `.Rd` is stale against
  the roxygen committed in `9cc4c15`. pkgdown and `?frs_cluster` would render the old
  text until it is committed.
- `tests/testthat/test-frs_cluster.R:68` and `:98` stub `DBI::dbGetQuery` with
  `if (grepl("DISTINCT species_code", sql))`. The resolver now emits
  `SELECT DISTINCT h.species_code`, which that pattern no longer matches. Dead either way
  — both tests pass `species = "CO"`, so the resolver never runs — but the stub is now
  stale and would silently return `data.frame(n = 10L)` as a species list for anyone who
  drops the argument.
- `.bkt_flags()` returns a named **atomic** vector, so `[["3"]]` on an absent key raises
  `subscript out of bounds` rather than returning `NULL`
  (`code-check-r.md`, "`[[` on a named ATOMIC vector"). testthat scores that under
  `error`, not `failed`, which still reddens, so the tests are safe — but a mutation probe
  counting only `$failed` would read those blocks as surviving.
- `.cds_fixture()` writes `edge_type = 1000` over the real FWA value
  (`test-frs_connectivity_wsg.R:316`). Harmless today — nothing on the downstream-cluster
  path reads `edge_type` — but `code-check-spatial.md`'s "FWA main flow is not edge type
  1000 alone" is the reason a future edge-type-sensitive assertion on that fixture would
  be testing a fiction. Same for the hardcoded `channel_width = 10`.
- `cluster_minimums`' `DISTINCT ON (cluster_id) … ORDER BY cluster_id, wscode_ltree,
  localcode_ltree, downstream_route_measure` does not end on a unique key, so a cluster
  holding two segments with identical codes and measure gets an arbitrary minimum, and
  phase 2 and phase 3 evaluate the CTE independently. Pre-existing, unchanged by this
  diff, and the brief's decision not to touch `DISTINCT ON`/`PARTITION BY` is about the
  group column rather than the tiebreak — flagging only because
  `code-check-r.md` prescribes ending on the candidate's own id.
- `tools:::.check_packages_used_in_tests(".", testdir = "tests/testthat")` is clean, so
  the new helper and test file add no undeclared `::`.
