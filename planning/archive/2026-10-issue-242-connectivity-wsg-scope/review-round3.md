# Code-check round 3 — fresh#242 (connectivity passes join a shared habitat table)

Asked for the mechanism behind rounds 1 and 2, plus a checkable enumeration of every
place it reaches. Not a verdict.

## Checklist read

| file | bytes | what I read |
|---|---|---|
| `code-check-infra.md` | 38,115 | **in full** (under 40,000). "Joining on a per-tenant key (e.g. `id_segment` per-WSG) against a multi-tenant table is cartesian" is this diff's subject; "Set `statement_timeout` + `lock_timeout`", "Two-statement DELETE/INSERT into a persist table is not atomic", "View vs. real table changes the planner's join direction", "Function-as-join-predicate" also read in that pass. |
| `code-check.md` | 330,698 | all **14** H3 under `## Mechanisms`, in full, `\|` table rows skipped. Plus **4** of the 23 standalone/Security/Spreadsheet H3s whose index lines name a shape this diff uses: "An assertion that matches an interpolated value cannot see the claim around it", "Do not edit files a long test run is reading", "An ordered dispatch makes severity ordering load-bearing", "A link to a repo-hosted artifact must be *tracked*". **19 H3s not read** (cloud/credential/URL/YAML/PDF/spreadsheet shapes absent from this diff). |
| `code-check-r.md` | 178,405 | **21** of 111 H3s in full: testthat error-vs-failed counting, `skip_if_not()` scope, `expect_gt(info=)`, "Tests that silently do not run", `expect_message` first-condition and `"$"`-anchor, Postgres row order, `sprintf("%g")` into SQL, `information_schema` lookup (incl. the correlated-subquery name-resolution paragraph), DBI driver types, `::text` spelling, `function(...)` mocks, `pkg::` in tests, `expect_false(identical())`, `[[` on a named atomic vector, `ifelse()` all-NA, testthat `tolerance`, zero-length `paste()`, `R CMD check` temp dir, `nzchar(NA)`, `match()` and NA. **90 not read.** |
| `code-check-shell.md` | 125,440 | index only. The diff contains no shell, no `git`/`gh`/`sed` invocation; `timeout` portability is referenced via `code-check.md`'s deadline rule. **~70 H3s not read.** |
| `code-check-spatial.md` | 155,517 | index only — no sf/terra/GDAL/bcdata call in the diff. The PostGIS used (`ST_ClusterDBSCAN`, `ST_DWithin`, `ST_Collect`, `ST_MakeLine`) is in-database SQL, which these headings do not cover; I did read "A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline" and "FWA `upstream_route_measure` misses the next segment's start" because the downstream fixture turns on FWA geometry semantics. **~95 not read.** |

Files I read in full from the tree: `R/frs_cluster.R`, `R/frs_habitat.R` 1180–1967,
`R/frs_habitat_classify.R` 70–418, `R/utils.R` (`.frs_wsg_in`, `.frs_validate_identifier`,
`.frs_db_execute`, `.frs_add_id_segment`, `.frs_index_working`),
`R/frs_order_child.R` 200–305, `R/frs_habitat_overlay.R` 150–290, `R/frs_break.R` 690–720,
`tests/testthat/helper-synthetic.R`, `tests/testthat/test-frs_connectivity_wsg.R`,
the new blocks in `test-frs_habitat_classify.R` and `test-utils.R`,
`data-raw/bucket_connected_check.R`, `data-raw/rear_wetland_floor_check.R`.

---

## The mechanism

One sentence: **every defect in rounds 1 and 2 came from an enumeration whose boundary
was drawn by the shape of the fix instead of the shape of the invariant, and the boundary
re-formed around each new fix.**

The invariant is a single fact: the habitat table's key is `(id_segment,
watershed_group_code)`. The fix chosen was "add the group to the joins". Everything that
followed inherited that framing, and each round found the class one axis over:

| axis | boundary the enumeration drew | what sat outside it | found by |
|---|---|---|---|
| **statement kind** | *joins* | aggregates with nothing to join (7 counts) and an R-side `id_segment NOT IN (<ids>)` list | round 1 |
| **function role** | *functions that read `habitat`* | the function that **writes** it — `frs_habitat_classify()`'s own count | round 2 |
| **predicate placement** | *the clause is present* | the clause's inner column resolving **outward**, so the predicate read as applied and matched every row | round 2 |
| **fixture axis** | *two groups, colliding `id_segment`* | the two groups **disagreeing** on the flag — the only configuration in which a duplicated CTE row changes an answer | round 2 |
| **artifact kind** | *code* | prose and examples that state the invariant or teach the join | **round 3, below** |

Three `code-check.md` rules name this as one rule, and all three prescribe the same
terminator:

- *"A guard's scope, escape hatches, and remedies"* — "**Terminate by enumeration, not by
  a reviewer saying you have converged: the class recurs one axis over**, and three 'this
  is now terminal' claims were wrong on one PR." Two have already been wrong on this PR
  (round 1's "seven sites" and round 2's "four unobservable").
- *"A fix lands in one of two callers that share a harness"* — "**the count is the
  signal, not the instance**: if you have fixed the same class twice in one of a pair,
  the pair is the bug." It has now been fixed in five functions and is still live in two
  (`frs_order_child()`, `frs_habitat_overlay()`).
- *"A fixture that cannot reach the failure mode"* — "**ask what the fixtures have in
  common and whether that shared property is the very thing the bug depends on.**" Round
  2 did exactly this and it is what un-blinded the four predicates.

And the specific sub-mechanism behind round 2's `.frs_wsg_in()` defect is already written
down, in `code-check-r.md` under "An `information_schema` lookup by the literal table
name misses what Postgres resolves": *"**A correlated subquery resolves names from the
inside out.** Qualify every outer column inside one … The tell is a subquery result that
is constant across rows."* Here it was the mirror — an **inner** column resolving
outward — with the same tell and the same silence.

**So the enumeration that terminates this is not over joins and not over functions. It is
over every artifact in the repository that states, relies on, or teaches the habitat
table's key.** The code half is now complete. The prose half is not, and it is the one
axis no round has crossed — by construction, because a `\dontrun{}` example cannot appear
in a mutation table and no test can go red for it.

---

## Enumeration — every statement in `R/` that reads or writes a habitat table

Verdict column: **S** = carries `watershed_group_code` (or `.frs_wsg_in()`); **n/a** =
single-group by construction; **U** = unscoped.

### `R/frs_cluster.R` — 13 sites, all S

| line | statement | verdict |
|---|---|---|
| 138–144 | `species = NULL` resolution, `EXISTS` against `table` | S (new) |
| 152–156 | `n_before` count | S via `.frs_wsg_in` |
| 175–179 | `n_after` count | S via `.frs_wsg_in` |
| 224–225 | `_upstream` `clustering` CTE, `h ⋈ s` | S (new) |
| 249–250 | `_upstream` `valid_clusters`, `h2 ⋈ st` | S (new) |
| 270–271 | `_upstream` final `UPDATE … FROM clustering` | S (new) |
| 310–311 | `_downstream` `clustering` CTE | S (new) |
| 340–341 | `_downstream` `has_connect` `EXISTS`, `s ⋈ h2` | S (new) |
| 393–394 | `_downstream` final `UPDATE` | S (new) |
| 468–469 | `_both` `tmp_clusters` CREATE, `h ⋈ s` | S (new) |
| 491–492 | `_both` phase 2, `h2 ⋈ st` | S (new) |
| 548–549 | `_both` phase 3 `LEFT JOIN h2` | S (new) |
| 606–609 | `_both` collapsed final `UPDATE` (+ `label_connect IS NOT TRUE`) | S (new) |

### `R/frs_habitat.R` — 14 sites, all S

| line | statement | verdict |
|---|---|---|
| 1371–1374 | `.frs_bucket_connected` `count_bucket()` | S via `.frs_wsg_in` |
| 1387 | `ANALYZE <habitat>` | n/a (statistics only; whole shared table, once per species × bucket × job) |
| 1402–1403 | `hab_join`, reused at 1404–1413 and 1438–1445 | S (#240) |
| 1475–1476 | bucket subtractive `UPDATE` | S (#240) |
| 1519–1522 | `.frs_distance_filter` `n_before` | S via `.frs_wsg_in` |
| 1537–1538 | distance-filter `UPDATE … FROM table s` | S (new) |
| 1543–1544 | distance-filter inner `NOT EXISTS`, `r ⋈ hr` | S (new) |
| 1577–1580 | `n_after` | S via `.frs_wsg_in` |
| 1783–1786 | `.frs_connected_waterbody` `n_before` | S via `.frs_wsg_in` |
| 1808–1809 | phase-1 `origins_sql`, `s2 ⋈ hr` | S (new) |
| 1840–1841 | `rearing_segs`, `s2 ⋈ hr` | S (new) |
| 1847–1848 | `spawn_upstream`, `s3 ⋈ hs` | S (new) |
| 1906–1914 | subtractive `UPDATE` (`FROM table s` + `NOT EXISTS`) | S (new) |
| 1943–1953 | additive `UPDATE` | S (new) |
| 1960–1963 | `n_after` | S via `.frs_wsg_in` |

### `R/frs_habitat_classify.R` — 4 sites

| line | statement | verdict |
|---|---|---|
| 229–239 | `CREATE TABLE IF NOT EXISTS` | n/a |
| 243–247 | idempotent `DELETE` per `wsg_codes` | S (by column) — see note A |
| 371–388 | per-species `INSERT`, group from `table` | S |
| 397–402 | verbose `acc/spn/rr` count | S via `.frs_wsg_in` (round 2's eighth site) |

### Still unscoped — both already deferred to #277

| line | statement | verdict |
|---|---|---|
| `frs_order_child.R:274` | `UPDATE h … WHERE h.id_segment = s.id_segment` | **U** — named in #277 |
| `frs_order_child.R:292–293` | `n_before` count, `WHERE species_code = %s` only | **U — the ninth count site, NOT named in #277** (finding 3) |
| `frs_order_child.R:298/302` | `n_added` = the unscoped `UPDATE`'s row count, printed as this job's | **U — not named in #277** (finding 3) |
| `frs_habitat_overlay.R:180–182` | `SELECT DISTINCT species_code FROM to` | **U** — #277; has no mandatory streams table to scope against (`bridge` optional) |
| `frs_habitat_overlay.R:261–275` | per-`(species, habitat_type)` `UPDATE` | **U** — #277 |

### `data-raw/` — both safe, stated so the enumeration is checkable

- `bucket_connected_check.R:68,78` join habitat↔streams on `id_segment` alone, but both
  temp tables are built `WHERE watershed_group_code = '<wsg>'`, so single-group. Safe.
- `rear_wetland_floor_check.R:109` already carries `AND h.watershed_group_code =
  s.watershed_group_code`. Safe.

**Complete sweep of aggregates:** `grep -rn "FILTER (WHERE" R/*.R` returns 23 hits. Nine
read a habitat table — `frs_cluster.R:153,176`, `frs_habitat.R:1372,1520,1578,1784,1961`,
`frs_habitat_classify.R:398`, `frs_order_child.R:292`. Eight carry `.frs_wsg_in()`; the
ninth is `frs_order_child.R:292`. The remainder read an access temp table
(`frs_habitat_classify.R:322`), a feature index, a near-river temp, a snap diagnostic, or
sit in roxygen examples (next section).

---

## Findings

### 1. **[bug]** `R/frs_habitat_classify.R:118` — the published view recipe joins on `id_segment` alone

```
#' # Join geometry back for mapping — id_segment links the two tables
#'   CREATE OR REPLACE VIEW fresh.streams_co_vw AS
#'   SELECT s.*, h.accessible, …
#'   FROM fresh.streams s
#'   JOIN fresh.streams_habitat h ON s.id_segment = h.id_segment
#'   WHERE h.species_code = 'CO'
```

Both tables are the multi-group persisted ones, and five lines below it the same example
says *"Run more WSGs later and both tables accumulate."* `CLAUDE.md` records the measured
cost of exactly this join: *"187 Naver Creek segments matched 22 groups; this was the
whole of #218"*, and prescribes *"always join on both"*. This is the documented way to
map results, it is what `CLAUDE.md`'s own "Views per species" line points at, and pkgdown
renders it.

It is in `\dontrun{}`, so nothing executes it — which is precisely why three rounds of
mutation tables and 16 new tests could not reach it. Same family in the same breath:

- `R/frs_network_segment.R:98` — prose, *"id_segment links back to fresh.streams for
  mapping"*, which is false for a multi-group `fresh.streams`.
- `R/frs_cluster.R:69`, `R/frs_habitat_classify.R:107–110`,
  `R/frs_network_segment.R:107–108` — three example `count(*) FILTER (…) FROM
  fresh.streams_habitat` aggregates with no group filter, i.e. the shape
  `.frs_wsg_in()` was added to fix, shown to users as the way to check results. The one
  at `frs_cluster.R:69` sits 60 lines above the new roxygen asserting other groups are
  "never read".

Fix: add `AND h.watershed_group_code = s.watershed_group_code` to the view, and either
`GROUP BY watershed_group_code, species_code` or a `WHERE watershed_group_code = …` to
the three count examples. `man/frs_cluster.Rd`, `man/frs_habitat_classify.Rd` and
`man/frs_network_segment.Rd` regenerate.

### 2. **[fragile]** `tests/testthat/test-frs_connectivity_wsg.R:525–552` — "species = NULL resolves only the species in this job's groups" cannot fail if that scoping is reverted

Measured, on its own fixture:

```
scoped resolution  -> BT
UNscoped resolution-> CH,BT
A shipped   (species = NULL)      own2=TRUE own3=FALSE CH=TRUE
B reverted  (species = c(BT,CH))  own2=TRUE own3=FALSE CH=TRUE
```

All three assertions hold identically. The reason is that the fix landed twice: with the
per-species passes now group-scoped, the extra species costs a full pass that **matches
nothing and writes nothing**, so it is observationally invisible at `verbose = FALSE`.
This is round 1's `OTHR3` finding one axis over — an assertion that holds under both the
shipped and the reverted code — and the test is named after the predicate it cannot see.

It is not worthless: `expect_false(own[["3"]])` would go red if the new `EXISTS` ever
over-narrowed to empty, which is the failure its own comment describes ("an empty species
vector runs the `for` body zero times"). But the title's claim is unpinned.

Make it decisive by asserting the *resolved list*, not the outcome — run with `verbose =
TRUE` and require the captured output to carry exactly one species line
(`expect_no_match(out, "CH")` plus a positive `expect_match(out, "BT")`), or spy
`DBI::dbGetQuery` and assert the returned codes. `code-check.md`, "An assertion that
matches an interpolated value cannot see the claim around it": prefer the positive
assertion, and terminate by enumerating the claim rather than reading it.

### 3. **[fragile]** `R/frs_order_child.R:292–293` and `:298/302` — #277's deferral names one of three affected artifacts

The accepted list records *"`frs_order_child()` … all issue #277"* on the basis of round
1's finding, which named "the same single-key additive UPDATE". The same function has two
more:

- line 292–293, a verbose `n_before` count with `WHERE species_code = %s` and no group —
  the **ninth** count site of the class whose other eight this branch fixed;
- line 298, `n_added <- DBI::dbExecute(conn, sql)`, reported at line 302 as `"+%d segments
  labeled %s = TRUE"`. Because the `UPDATE` itself is unscoped, that row count includes
  every other group's rows it flipped.

Both are `message()`, not `cat()`, so a `capture.output()`-style test would not see them
either. Write all three into #277's body, or the fix lands on the `UPDATE` and the two
numbers keep reporting other groups' rows as this job's — the "A fix lands in one of two
callers" shape, inside one function.

### 4. **[fragile]** `tests/testthat/test-frs_connectivity_wsg.R:7–10` — the file's own coverage claim is false for 6 of 16 blocks

The header states: *"Each also asserts an expected keep AND an expected strip on this
group, so neither a no-op nor a strip-everything mutant passes."* Counted mechanically
over the file:

```
<<  true=1 false=0  another group's rows do not inflate the downstream trace distance  (:153)
<<  true=0 false=0  the verbose progress lines count this job's groups                 (:409, expect_match)
<<  true=0 false=1  another group's rearing on an id this group calls FALSE …          (:474)
<<  true=0 false=1  the same holds for the upstream direction's clustering CTE          (:500)
<<  true=0 false=1  the same holds for the downstream direction's clustering CTE        (:555)
<<  true=0 false=1  another group's spawning does not lend lake adjacency …             (:599)
```

So a **strip-everything** mutant passes all four axis tests and the lake test, and a
**no-op** mutant passes `:153`. The suite as a whole still covers both directions
(`:131` and `:180` carry the pairs), so this is a wrong written claim rather than a
coverage hole — which is the same artifact round 2 found when this branch's own write-up
called four predicates "unobservable". Either add the missing counterpart assertion to
each of the five, or narrow the sentence to name which blocks carry the pair.
`code-check.md`, "A guard that fails toward pass": *a rule stated in a comment is not an
enforced rule — where a comment says "never X", grep the file for X before believing it.*

### 5. **[fragile]** `tests/testthat/test-frs_connectivity_wsg.R:555–596` — the downstream-CTE pin has a silent wrong-reason pass, gated on data nothing asserts

`bridge_gradient = 1` is justified only in a comment (`:270–272`, *"keeps real gradients
out of play"*). If the invalid stream's **lowest** segment has `gradient >= 1`, then under
the restored defect `nearest_barrier` and `nearest_connect` are the same row at `rn = 1`,
`WHERE b.rn IS NULL OR b.rn > a.rn` is FALSE, the cluster is invalid anyway, `b[3]` is
stripped, and `expect_false` **passes with the predicate removed**. Under the shipped code
`nearest_connect` is empty, so the gradient never enters — i.e. the premise only matters
in the direction that proves the guard.

Measured on this database, the pin is live today:

```
.cds_pick() -> wsg ADMS, valid 356033104, invalid 356034674
  blue_line_key    n  n_wscode  max_grad   min_len
      356033104    3         1    0.5115  215.4409
      356034674    3         1    0.6839  371.2947
```

0.68 against a threshold of 1, on a pick that is ordered by `blue_line_key` and therefore
free to move with the database. Add `AND gradient < 1` to `.cds_pick()`'s `cand`
predicate (or `max(gradient) < 1` to its `HAVING`), or assert the measured max after
`.cds_fixture()`. The two sibling tests at `:363` and `:380` fail *loudly* in that case,
because their `expect_true(own[[a[2]]])` goes red — only this one fails silently.

### 6. **[fragile]** `tests/testthat/test-frs_connectivity_wsg.R:599–677` — the lake-adjacency pin is the sole coverage of `lake_adjacent = TRUE`, behind four data-dependent skips

Four `skip_if()` guards (`:625`, `:660`, `:661`, `:667`), each on live FWA geometry, and a
skip there reads identically to a pass in a summary line. It is the only test in the suite
that exercises `lake_adjacent = TRUE`'s whole-cluster credit — `.cwb_run()` passes
`lake_adjacent = FALSE`, and the default in `.frs_run_connectivity()` is `TRUE`. So
`code-check-r.md`, "Tests that silently do not run", applies verbatim: *"a suite where the
only coverage of a behaviour sits behind a skip has no coverage of it."*

Measured on this database it does run — all three premises hold on the first
`area_ha >= 10` lake by `waterbody_key`:

```
near(6) [0..500]       = TRUE    (required TRUE)
near(5) [500..1500]    = FALSE   (required FALSE)
near(4) [30000..31000] = FALSE   (required FALSE)
```

Make the vacuity visible rather than tightening it (`code-check.md`, "A fixture that
cannot reach the failure mode": *print `VACUOUS: <guard> — <arm> never ran`*): loop
candidate lakes by `waterbody_key` until one satisfies all three premises instead of
taking the first, and keep a single `skip_if` for "no lake in this database satisfies
them" so a skip means something specific.

---

## Answers to the four specific questions

### 1. Is the predicate set complete? Is there a third caller, count site or list the `.frs_wsg_in()` work still misses?

**In the five functions the branch touched: complete.** All 31 habitat-reading or
-writing statements across `frs_cluster.R`, `frs_habitat.R` 1180–1967 and
`frs_habitat_classify.R` carry the group — the table above lists each with its line and
verdict, derived by parsing rather than recollection (`grep -rn "FILTER (WHERE"` for the
aggregates; `grep -n "habitat"` + a read of every `sprintf()` argument list for the
joins and UPDATEs).

**Outside them: two exported functions, already #277 — but #277 as written covers one of
the three artifacts in `frs_order_child()`** (finding 3). `frs_habitat_overlay()` has a
genuine blocker #277 will have to resolve: its species resolution and its UPDATE have no
mandatory streams table to scope against, since `bridge` is optional, so it needs a
different mechanism (a `watershed_group_code` in `by`, or an `information_schema`-style
branch on whether `to` carries the column — `code-check-infra.md` prescribes exactly that
branch for this case).

**Note A — `.frs_wsg_in()`'s grain, and the one condition it depends on.** The clause
scopes to *the watershed groups present in `table`*, which is **coarser** than `table`
itself in custom-AOI mode (`frs_habitat(wsg = NULL, aoi = …)`, or `wsg` with an additive
`aoi`): a partial-AOI working table resolves the whole group. It is nevertheless exact for
the habitat table, because `frs_habitat_classify(overwrite = TRUE)` — the default, and what
`frs_habitat()` always uses — `DELETE`s every row of each group before inserting
(`frs_habitat_classify.R:243–247`), so at most one job's rows for a group ever coexist.

That is a dependency worth writing down rather than leaving implicit. With
`overwrite = FALSE` (exported, caller-settable) two partial-AOI runs in one group **can**
coexist in a shared `to_habitat`, and their break-created segments collide: new ids are
`(SELECT max(id_segment) FROM <table>) + row_number()` per working table
(`R/frs_break.R:697–700`). Every predicate this branch added is blind to that collision,
because it is intra-group. One sentence in `frs_cluster()`'s roxygen, or a line in #277.

**Note B — one fact derived twice, harmlessly.** `frs_habitat_classify()` already holds
`wsg_codes` (line 163, `SELECT DISTINCT watershed_group_code FROM <table>`) and the new
count at line 402 re-derives the same fact through `.frs_wsg_in(table)`. Same producer, so
they cannot diverge — not a defect, but the count could read `wsg_codes` and the two
derivations would become one.

### 2. Is the `phase1_ids` removal equivalent for a single-group run?

**Yes, in every case named.** Walked:

- **The identity.** Every row the new `UPDATE` targets is joined to a `tmp_clusters` row
  on `(id_segment, watershed_group_code, species_code)`, and `tmp_clusters` holds exactly
  the habitat rows with `label_cluster IS TRUE` for that species. So on a target row
  "phase 1" — `label_cluster AND label_connect` — reduces to `label_connect IS TRUE`, and
  the protection is its complement. The roxygen at `:448–455` states this correctly.
- **`label_cluster == label_connect`.** Old: `phase1_ids` = every id with the label TRUE =
  exactly `tmp_clusters`' ids, so the `NOT IN` excluded every target → 0 rows. New: every
  target has the label TRUE, so `IS NOT TRUE` is FALSE → 0 rows. Equivalent. (Reachable
  in principle via `requires_connected: spawning` on a spawn rule, through
  `.frs_run_connectivity()` line 1287–1291 where `label_cluster = "spawning"`.)
- **NULL vs FALSE.** Old: `label_connect IS TRUE` excluded NULL from `phase1_ids`, so a
  NULL-connect row was **not** protected. New: `IS NOT TRUE` is TRUE for NULL, so it is
  **not** protected. Equivalent, and pinned by `expect_false(own[["6"]])` at `:149` — a
  `h.<label_connect> = FALSE` spelling would leave the row untouched and turn that
  assertion red, so the test is decisive for the spelling as well as the semantics.
- **The two collapsed branches.** The old `""` branch fired only when `phase1_ids` was
  empty, which means no row of the species carries both labels, which means no target row
  has `label_connect IS TRUE`, which means the always-present new clause excludes nothing.
  Equivalent.
- **The read moved later.** Nothing between the old `dbGetQuery()` and the `UPDATE` writes
  `label_connect`: `_both` writes only `label_cluster`, and phases 2 and 3 are `SELECT`s.
  Equivalent.

Pinned by `expect_true(own[["5"]])` at `:148` (deleting `AND h.<label_connect> IS NOT TRUE`
strips the on-spawning segment in invalid cluster D → red) and `expect_false(own[["6"]])`
at `:149`.

### 3. Does the `.frs_connected_waterbody()` subtractive rewrite change which rows of *this* group get cleared?

**No, for any row of `table`.** `NOT IN (SELECT id_segment FROM qual)` → `FROM <table> s …
AND NOT EXISTS (SELECT 1 FROM qual q WHERE q.id_segment = h.id_segment)`:

- every id in `qual_tbl` comes from `table` (both inserts project `table.id_segment` —
  lines 1819–1823 and 1869–1895), and `id_segment` is unique within `table`, so once `h`
  is pinned to a row of `table` the two forms select the same set;
- `NOT IN`'s fail-open on a NULL in the list is gone, which can only widen the clear, and
  only in a state that cannot arise (see the caveat below).

One behaviour change, and it is in the safe direction and deliberate: a habitat row of
this group whose `id_segment` is **not in `table` at all** is no longer cleared. That can
arise only if `table` was re-segmented smaller after `habitat` was written; such a row is
stale either way, and classify's group `DELETE` removes it on the next run.

Minor: the comment at `:1904–1905` says `NOT EXISTS` "drops `NOT IN`'s fail-open
behaviour on a NULL id, **which qual_tbl cannot hold (every id in it comes from
`table`)**". Coming from `table` does not by itself make it non-NULL — what makes it
non-NULL is `.frs_add_id_segment()` (`R/utils.R:574–577`) filling it from
`linear_feature_id`. The claim is true; its stated reason is not the one that supports it.
`code-check.md`: *a comment stating a property is an unexecuted claim.*

### 4. Does `.frs_wsg_in()` compose correctly at each of the eight sites?

**Yes at all eight.** The clause is
`" AND watershed_group_code IN (\n         SELECT s.watershed_group_code FROM <table> s)"`.

| site | placeholders in format | args | outer habitat alias | preceding `WHERE` condition |
|---|---|---|---|---|
| `frs_cluster.R:152–156` | 4 | 4 | none | `species_code = …` |
| `frs_cluster.R:175–179` | 4 | 4 | none | `species_code = …` |
| `frs_habitat.R:1371–1374` | 4 | 4 | none | `species_code = …` |
| `frs_habitat.R:1519–1522` | 4 | 4 | none | `species_code = …` |
| `frs_habitat.R:1577–1580` | 4 | 4 | none | `species_code = …` |
| `frs_habitat.R:1783–1786` | 3 | 3 | none | `species_code = …` |
| `frs_habitat.R:1960–1963` | 3 | 3 | none | `species_code = …` |
| `frs_habitat_classify.R:397–402` | 3 | 3 | none | `species_code = …` |

- **Leading space:** present, and every site appends directly after `= %s` with no
  separator, so it is load-bearing. ✓
- **Placement:** last condition of a `WHERE` that already has one, at all eight. ✓
- **Unaliased habitat:** at all eight, so the outer `watershed_group_code` resolves to the
  habitat relation — which is what the roxygen assumes and what round 2's qualified inner
  column depends on. ✓
- **`sprintf()` arity:** verified above; no site is off by one, and the clause's own `%`
  cannot be re-parsed because it reaches the outer `sprintf()` as an **argument**, never
  as part of a format string (`code-check-r.md`, `sprintf("%g")` entry's note about a
  literal `%` in a template). ✓
- **NULL semantics:** `x IN (SELECT …)` containing a NULL yields NULL rather than TRUE for
  a non-match, so the row is **excluded**. The clause therefore fails toward an
  under-count, not an over-count — the safe direction, and the opposite of what a `NOT
  IN` here would have done. ✓
- **Index support:** `.frs_index_working(conn, to)` (`frs_habitat_classify.R:415`) creates
  single-column indexes on both `watershed_group_code` and `species_code`
  (`R/utils.R:645–668`), so the eight counts are not full scans on a province-sized shared
  table. ✓

One wording point, same artifact round 1 flagged: `frs_cluster()`'s roxygen still says
other groups' rows *"are never read or cleared"*. After the fix they are never **counted**
and never **written**, but they are still read — `.frs_wsg_in()` filters them, and the
`species = NULL` resolution scans the whole habitat table by construction. The operative
claim is "no other group's row can change this job's result, and none is written". Low
stakes, but it is exported, pkgdown-rendered prose, and it is the sentence whose first
version cost round 1 seven fixes.

### On the downstream fixture's discovery predicate (asked in "WHAT I MOST WANT CHECKED" 4)

**The predicate is sufficient.** `.frs_cluster_downstream()`'s trace is
`whse_basemapping.fwa_downstreamtrace(blk, drm)`, which descends the wscode hierarchy, so
stream A can appear on B's downstream path only if `A.wscode_ltree` is an **ancestor** of
`B.wscode_ltree`. `NOT a.wscode_ltree <@ b.wscode_ltree AND NOT b.wscode_ltree <@
a.wscode_ltree` excludes both directions, and `<@` includes equality, so an identical pair
is excluded too. Both candidates are mainstems (`blue_line_key = watershed_key`) in one
watershed group, so there is no same-blue-line path either.

Two residuals, neither live on this database:

- **The population is still defined twice, one axis in.** `cand` groups by
  `(blue_line_key, wscode_ltree)` and bounds the count 3–8; `.cds_fixture()` inserts every
  row of the blk in the group that is a mainstem, **without** the `wscode_ltree`
  restriction. A blue line carrying two wscodes therefore contributes segments the
  candidate query never counted. Measured: `n_wscode = 1` for both picked blks, so not
  live — and the flagging is by rank (`a[1]`, `a[2]`, `b[-1]`) rather than by count, so
  extra rows would not misdirect it. Round 1 closed the group and mainstem halves of this;
  the wscode half is open.
- **`.cds_pick()` does not require the two streams to be more than 1 m apart**, so
  `ST_ClusterDBSCAN(geom, 1, 1)` could merge them into one cluster, at which point the
  `keep` and `strip` assertions describe the same cluster and contradict each other. That
  fails **loudly**, so it is a fixture fragility rather than a silent pass. Adding
  `ST_Distance` to the pick would close it.

---

## Not re-flagged (accepted list honoured)

Hardcoded column name rather than `.frs_opt()`; `frs_cluster()` now requiring
`watershed_group_code`; temp tables other than `tmp_clusters` carrying `id_segment` alone;
the group absent from every `PARTITION BY` / `DISTINCT ON` / `GROUP BY`;
`frs_order_child()`'s and `frs_habitat_overlay()`'s UPDATEs, the custom-AOI persist
`DELETE` and the habitat table's missing unique index as #277; the fixed table names at
`test-frs_cluster.R:153` and `test-utils.R:33`.

Checked and clean, so stated rather than listed as findings: a failed `expect_match` does
**not** abort a `test_that()` block (measured on testthat 3.3.2), so all four assertions in
the `:409` verbose test execute; each of those four regexes carries the `n_after` number,
which is the only part of the line that differs between the scoped and unscoped count, so
all four are decisive; `local_mocked_bindings()` beneath the `testthat (>= 3.0.0)` pin is
pre-existing and used in 20 other test files; `.frs_db_execute()` has exactly the two
formals the new mock declares; the new `test-utils.R:272–281` block is what catches round
2's unqualified inner column, which `test-frs_habitat_classify.R`'s two `expect_match`es
cannot (both match under that defect).

One live caveat on `test-frs_habitat_classify.R:617–618`: `skip_if(length(counts) == 0,
"the classifier did not reach its progress count under mocking")` is a guard that fails
toward **skip**. I traced the mocked path and it does reach line 397 today
(`gate = FALSE`, `models` all `cw`, `near_specs` empty, `.frs_index_working()` returns
early on a non-`DBIConnection`), but any future real DB call added upstream of the count
turns this pin silently green-by-skip rather than red. A `expect_gt(length(counts), 0)` in
place of the `skip_if` would make the vacuity loud; the `tryCatch(error = …)` already
preserves `seen`, so a genuine abort would still yield the SQL.
