# Findings — Custom-AOI persist deletes other watershed groups' rows from to_streams (#282)

## Issue context

**If done:** persisting a custom-AOI job into a shared `to_streams` removes only
that job's rows, so a table accumulating several watershed groups keeps every
group's. **If never:** each custom-AOI job silently deletes rows belonging to
other groups whose `id_segment` values collide, and the INSERT that follows puts
back only its own — so the rows are gone, from a persisted table, with no error.

### Problem

Both job paths in `frs_habitat()` delete by watershed group when `wsg` is given,
and fall back to `id_segment` when it is not:

```r
if (!is.null(wsg_code)) {
  DELETE FROM <to_streams> WHERE watershed_group_code = <wsg>
} else {
  DELETE FROM <to_streams> WHERE id_segment IN (SELECT id_segment FROM <streams_tbl>)
}
```

`R/frs_habitat.R`, in the `to_streams` block of each path. In custom-AOI mode
(`wsg = NULL`) the second branch runs, and `id_segment` is unique only **within**
a watershed group — each working table numbers its segments independently from
`max(id_segment) + row_number()` (`R/frs_break.R`). So the DELETE matches rows of
every group in `to_streams` that happens to share a value, and the INSERT
immediately after writes back only this job's.

### Why this one is different from the rest of the family

#242 fixed the connectivity passes; #277 covers three exported functions in the
same class. All of those set a **flag** wrongly — recoverable by re-running the
pass. This one **removes rows** from a persisted table. Re-running the job that
caused it does not restore them; the groups it damaged have to be re-segmented,
and nothing records which they were.

It is also outside the #231 umbrella's workplan, which is scoped to habitat-table
operations (its body's mechanism is general, but its title and sub-issue list are
not). `to_streams` is a streams table.

### Not yet measured (per the issue body)

- Does any current workflow actually run `frs_habitat()` with `wsg = NULL` **and**
  a shared `to_streams`? link uses per-WSG working schemas, so probably not
  there.
- A custom AOI can itself span groups, in which case the job's own `streams_tbl`
  holds several — so the fix is to delete on the pair, which the working table
  carries.

### Proposal (per the issue body)

Delete on `(id_segment, watershed_group_code)` in the fallback branch, matching
what the WSG branch already does by group. The working table carries both
columns, so this needs no new data. One fixture, in the shape of
`tests/testthat/helper-synthetic.R` from #242: a second group's rows in
`to_streams` sharing `id_segment` values, which must survive a custom-AOI
persist.

Relates to #242, #277, #231, #218.

## Exploration, 2026-10-28

### The two call sites

| site | path | delete when `wsg_code` is NULL |
|---|---|---|
| `R/frs_habitat.R:515` | sequential | `DELETE FROM <to> WHERE id_segment IN (SELECT id_segment FROM <from>)` |
| `R/frs_habitat.R:675` | mirai | same statement, written with `DBI::dbExecute` and `'%s'` interpolation |

The two blocks are otherwise the same work — `CREATE TABLE IF NOT EXISTS … LIMIT
0`, `.frs_persist_columns()`, delete, insert — which makes them the "fix lands in
one of two callers that share a harness" shape (`code-check.md`). Hence the plan's
helper extraction rather than two parallel edits.

### Package internals do reach the mirai daemon

Neither `.frs_persist_columns()` nor `.frs_enrich_breaks()` nor
`.frs_validate_gradient_thresholds()` is in `NAMESPACE`, yet the parallel closure
at `R/frs_habitat.R:563` calls all three unqualified. The closure is serialized
with its environment, whose parent is `namespace:fresh`; namespace environments
serialize by name, so the daemon's `library(fresh)` resolves them. Consequence
for testing: the daemon gets the **installed** package, so a `devtools::load_all()`
test cannot exercise the parallel path's new helper. That is why Phase 3 carries
a static enumeration check as well as a runtime one.

### The shipped example teaches the dangerous call

`man/frs_habitat.Rd:211-217`:

```r
# Custom AOI — sub-basin via ltree filter
frs_habitat(conn,
  aoi = "wscode_ltree <@ '100.190442.999098'::ltree",
  species = c("BT", "CO"),
  label = "richfield",
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat")
```

Custom-AOI mode into a shared `fresh.streams`. So the issue's first open question
is answered: a documented workflow reaches this. Same shape as #242's finding
that the published `frs_habitat_classify()` example taught the join that release
fixed.

### `watershed_group_code` nullability

```sql
SELECT count(*) AS n_null FROM whse_basemapping.fwa_stream_networks_sp
 WHERE watershed_group_code IS NULL;                      --> 0
SELECT is_nullable, data_type FROM information_schema.columns
 WHERE table_schema = 'whse_basemapping'
   AND table_name = 'fwa_stream_networks_sp'
   AND column_name = 'watershed_group_code';              --> NO, character varying
```

Run against the default `frs_db_conn()` on 2026-10-28. `NOT NULL` with no nulls,
so on FWA `=` would be safe. fresh is network-agnostic (`CLAUDE.md`, "Design
principles"), and a spyda-built network's column need not be, so a NULL in it is
the silent-no-op direction: `=` against NULL matches nothing.

**What shipped is `watershed_group_code = '<code>'`, not `IS NOT DISTINCT
FROM`.** The NULL case is handled where it generalises instead — the guard in
`.frs_persist_streams()` refuses any target holding rows whose *key* is NULL,
whichever of the three keys the job uses, so the hazard is closed for
`linear_feature_id` and `id_segment` as well, and a row that no delete can ever
match is reported rather than quietly worked around. A predicate change would
have covered one key of three. Correcting the earlier plan text, which said the
predicate would carry it.

### `id_segment` numbering — the first reading was wrong

**Retracted.** This section first said numbering "restarts at 1 every job",
following the issue body. The plan review disproved it against the code and I
confirmed it: `.frs_add_id_segment()` (`R/utils.R:571-577`) sets

```sql
UPDATE <table> SET id_segment = linear_feature_id WHERE id_segment IS NULL
```

so base segments carry the FWA primary key, globally unique, and only segments
*created by breaking* get `(SELECT max(id_segment) FROM <table>) + row_number()`
(`R/frs_break.R:697-701`). Those are the only two assignment sites in `R/`, and
`git log -L 571,578:R/utils.R` shows this one unchanged since it was introduced
(`0995567`, #84).

The same wrong mechanism is in issue #282's body and in **shipped `NEWS.md`
0.46.0** ("each working table numbers its segments from
`max(id_segment) + row_number()`"). Correcting both is a Phase 0 task.

### …but the persisted table is the opposite, and that is what the examples target

Measured on the default `frs_db_conn()` target, 2026-10-28, with
`SET statement_timeout = 240000`:

```sql
SELECT count(*) n_rows, count(DISTINCT watershed_group_code) n_groups,
       sum((id_segment =  linear_feature_id)::int) n_base,
       sum((id_segment <> linear_feature_id)::int) n_derived
FROM fresh.streams;
--> 3,802,814 | 98 | n_base = 0 | n_derived = 3,802,814

SELECT watershed_group_code, count(*) n, min(id_segment), max(id_segment),
       min(linear_feature_id), max(linear_feature_id)
FROM fresh.streams WHERE watershed_group_code IN ('BULK','COTR') GROUP BY 1;
--> BULK  87,639 rows  id 1..87,639   lfid 17,000,014..868,144,543
--> COTR  36,815 rows  id 1..36,815   lfid 700,821,184..868,144,477

SELECT count(*) FROM (SELECT id_segment FROM fresh.streams
  GROUP BY id_segment HAVING count(DISTINCT watershed_group_code) > 1) z;
--> 113,305 id_segment values appear in more than one group

SELECT count(*) FROM (SELECT id_segment, watershed_group_code FROM fresh.streams
  GROUP BY 1,2 HAVING count(*) > 1) z;
--> 0 duplicate (id_segment, watershed_group_code) pairs
```

`id_segment` in `fresh.streams` is a **per-group 1..n sequence** with no row equal
to its `linear_feature_id`. Every one of COTR's 36,815 ids also exists in another
group. That reconciles #218's measurement exactly (187 Naver Creek segments
matching 22 groups), which the review had called impossible because it could
reach no `fresh` schema.

Current `main` cannot produce a per-group 1..n sequence, so `fresh.streams` was
built by an older pipeline — the `frs_habitat_partition` / `frs_habitat_species`
era, since removed. **Consequence: the right delete key depends on which table
generation is being written**, which is why the key decision is re-opened in
Phase 0:

| target | residual collisions | pair key |
|---|---|---|
| `fresh.streams` as it stands | cross-group, total (113,305 shared ids) | fixes the loss; preserves a key that currently holds |
| freshly built under current code | same-group (review measured 76 of 245 derived ids on a 434-row AOI) | changes nothing, and would create duplicate pairs |

### Sibling defect: `to_barriers` deletes by blue_line_key alone

`R/frs_habitat.R:532` and `:690`:

```sql
DELETE FROM <to_barriers> WHERE blue_line_key IN (SELECT DISTINCT blue_line_key FROM <grad_tbl>)
```

The comment calls it "idempotent delete by BLK (works for both WSG and custom
AOI)". It does not, where a blue line crosses a group boundary:

```sql
SELECT count(*) AS blks_spanning_groups FROM (
  SELECT blue_line_key FROM whse_basemapping.fwa_stream_networks_sp
  GROUP BY blue_line_key HAVING count(DISTINCT watershed_group_code) > 1) q;
--> 259
```

259 blue lines, measured 2026-10-28. A job on one of them deletes the other
group's barriers on that line and inserts only its own. This one is **not**
confined to custom-AOI mode — the barriers delete is unconditional, so the WSG
path hits it too.

The projection to widen is the **multiclass** arm, `R/frs_break.R:350-358`
(`blue_line_key, downstream_route_measure, max(gradient_class), 'gradient',
'attribute'`), which is what `frs_habitat()` reaches: it passes
`classes = grad_classes` with no `threshold`, and `frs_break_find()` dispatches
on that (`R/frs_break.R:147`). The first draft of this file cited the
single-class projection at `:225-231`, which `to_barriers` is never built from —
corrected after the plan review. `.frs_enrich_breaks()` adds only the two ltree
columns, so either way there is no `watershed_group_code` to scope by and fixing
it means widening that schema. Gate decision: separate issue, filed in Phase 4.

### Scoped-site audit — two of four were misclassified

**Corrected after the plan review.** The first pass asked *does the DELETE name
`watershed_group_code`* when the question is *is the group set the right scope*.
That is the reassuring direction of wrong, so it went unchallenged.

Genuinely fine:

- `R/utils.R:478` `.frs_near_river_sql()` — carries
  `AND n.watershed_group_code = s.watershed_group_code`.
- `R/frs_network_segment.R:206` — `DELETE … USING` on `ctid` + position, not
  keyed on `id_segment`.

**Not fine, and bigger than #282** — both verified 2026-10-28:

- `R/frs_habitat_classify.R:170-172` derives `wsg_codes` as
  `SELECT DISTINCT watershed_group_code FROM <working streams table>`, then
  (`:249-255`) deletes **whole groups** from the shared habitat table. In
  custom-AOI mode that removes every row of every group the AOI touches and
  inserts only the AOI's rows.
- `R/frs_near_river.R:155-158` has the identical shape, against a target
  `R/frs_habitat_classify.R:208` makes shared (`paste0(to, "_near_river")`). Its
  comment states the intent outright: *"A custom AOI need not be one group, so
  delete every group the table holds."*

Filed as its own issue in Phase 0, not fixed on this branch — but it cannot be
recorded as "no change needed", and this branch's NEWS must not imply custom-AOI
persist is safe while the habitat side loses more. Adjacent to #225 (open) and
#163 (closed, and literally an audit of whether these functions are per-AOI).

The remaining `id_segment`-only joins under `R/frs_cluster.R`,
`R/frs_habitat_overlay.R`, `R/frs_order_child.R` and `R/frs_feature_index.R` are
#242's and #277's territory, not this branch's.

### Test patterns available

- `tests/testthat/test-frs_habitat.R` already holds live integration tests for
  the persist path: `skip_if_not(.frs_db_available(), "DB not available")`, a
  small ltree AOI (`'100.190442.999098.995997.058910.432966'`), `working.*`
  output tables, `on.exit()` dropping them. Phase 1's test follows it.
- `tests/testthat/helper-synthetic.R` holds #242's `pg_temp` fixture, including
  `.bkt_habitat_add()`, whose whole purpose is a second group's rows at colliding
  `id_segment` values. Useful as the model for the decoy row even though this
  branch's table is a streams table.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| Plan built on the issue's stated mechanism (`id_segment` "restarts per job"), which the code contradicts | Read `.frs_add_id_segment()` (`R/utils.R:571-577`) and `git log -L` on it; enumerate the two assignment sites rather than trusting the issue body. Phase 0 now corrects the issue and `NEWS.md` 0.46.0. |
| Review reported #218's measurement "impossible" because it could reach no `fresh` schema | The default `frs_db_conn()` does reach it. A subagent's negative about data availability is about its connection, not the world — re-probe before accepting it. |
| Scoped-site audit passed two sites it should have failed | Asked "does the DELETE name the column" instead of "is the group set the right scope". Re-audit by what the scope *selects*, not by which identifiers appear. |
| Province-wide `blue_line_key` aggregate times out on some connections | `DBI::dbExecute(conn, "SET statement_timeout = 240000")` before the query; `CLAUDE.md` prescribes `statement_timeout` + `lock_timeout` on long DB ops. |

## Phase 0, 2026-11-01 — the key decision, measured on the table the fix writes

All queries against the default `frs_db_conn()` target with
`SET statement_timeout` / `lock_timeout`. Scripts:
`/private/tmp/.../scratchpad/phase0_{target,working,b2,b3,c}.R` (scratch, not
committed — every query is reproduced inline below).

### A. The persisted target `fresh.streams`, re-verified today

| measure | value |
|---|---|
| rows / groups | 3,802,814 / 98 |
| `id_segment = linear_feature_id` (base) | **0** |
| `id_segment <> linear_feature_id` (derived) | 3,802,814 |
| duplicate `(id_segment, watershed_group_code)` | **0** |
| duplicate `(linear_feature_id, downstream_route_measure)` | **0** |
| `id_segment` values in >1 group | 113,305 |
| `linear_feature_id` in >1 group | **0** |
| `downstream_route_measure` integral / fractional | 2,518,505 / 1,284,309 |

Unchanged from 2026-10-28, so `research/id_segment_identity.md` still holds.
Column types: `id_segment integer`, `linear_feature_id bigint`,
`downstream_route_measure double precision`, `watershed_group_code varchar`.

### B. What a current-code custom-AOI job actually brings

`frs_habitat(aoi = "wscode_ltree <@ '100.190442.999098.995997.058910.432966'",
species = "CO")` — 464 rows, one group (ADMS), **189 base / 275 derived**, and
within the job 0 duplicates on `id_segment` alone, on the pair, and on
`(linear_feature_id, downstream_route_measure)`.

The review's earlier figures (434 rows, 189 base / 245 derived) were the same AOI
with a different species set — the base count is identical and only the break
count moves, because `breaks_gradient` auto-derives from the species' spawn/rear
maxima. Not nondeterminism: see D.

**Against `fresh.streams` itself, all three candidate keys delete 0 rows** — ADMS
is not among its 98 groups, and the two id spaces do not overlap anyway (a job's
ids are `linear_feature_id`-scale, 1e7–9e8; the table's are 1..n per group,
max 87,639). So the #282 loss does not materialise against the *legacy* table at
all. It materialises against a target built by **current** code, which is what the
blast radius below measures.

### C. Blast radius in the id space (the generalizable number)

Which real FWA segments share this job's `id_segment` values — i.e. which rows a
target holding those groups would lose:

```sql
WITH job AS (SELECT DISTINCT id_segment,
               bool_or(id_segment = linear_feature_id) AS is_base
             FROM <job rows> GROUP BY id_segment),
     jg AS (SELECT DISTINCT watershed_group_code FROM <job rows>)
SELECT CASE WHEN j.is_base THEN 'base id' ELSE 'derived id' END,
       CASE WHEN n.watershed_group_code IN (SELECT * FROM jg)
            THEN 'same-group' ELSE 'other-group' END,
       count(*)
FROM job j JOIN whse_basemapping.fwa_stream_networks_sp n
  ON n.linear_feature_id = j.id_segment
GROUP BY 1,2;
--> base id   | same-group | 189
--> derived id| same-group |  81
--> (no other-group rows at all)
```

**81 of the 275 derived ids name a real FWA segment, and every one of them is in
the job's own group.** 0 other-group. So on a current-code-built table the
residual collision is **same-group**, which confirms the review's B2/B3 and
settles the re-opened decision: **the pair key fixes nothing here.** It also
cannot be assumed unique, because those 81 derived ids each equal a real
same-group `linear_feature_id`.

Physical identity cannot reach another group by construction, and it is measured:

```sql
SELECT count(*) FROM <job rows> s
JOIN whse_basemapping.fwa_stream_networks_sp n
  ON n.linear_feature_id = s.linear_feature_id
WHERE n.watershed_group_code IS DISTINCT FROM s.watershed_group_code;  --> 0
```

### D. A third key the plan did not consider: the parent segment

`.frs_resolve_aoi()` (`R/utils.R:941-1000`) returns a **row predicate** in every
arm — `&&`, `ST_Intersects`, a table lookup. There is no `ST_Intersection`,
`frs_clip()` or `ST_LocateBetween` anywhere in `R/frs_habitat.R`,
`R/frs_extract.R` or `R/frs_network_segment.R`, so **an AOI never truncates a
segment at its boundary** — a job holds all of the ground each segment it
touches covers. `frs_break_apply()` does cut geometry (`ST_LocateBetween`), but
that is subdivision inside the job, not clipping at the AOI edge, which is why
deleting by parent segment is complete rather than partial.

That makes `DELETE … WHERE linear_feature_id IN (SELECT linear_feature_id FROM <from>)`
a complete and correct partition overwrite, and it is the only candidate that is
correct against **both** table generations:

| | pair key | physical identity | parent segment |
|---|---|---|---|
| can delete another group's rows | no, while the pair stays unique | **never** (0 lfids span groups, province-wide) | **never** (same) |
| fixes the same-group residual (81 ids) | **no** | yes | yes |
| clears stale broken rows left by an earlier, differently-broken run | no | no | **yes** |
| correct against legacy `fresh.streams` | no — id spaces disjoint, deletes nothing | partly — see below | yes |
| float comparison in the predicate | none | `double precision` `=` | none (`bigint`) |

The legacy row of that table, measured:

```sql
SELECT count(*) AS n_bulk_rows,
       sum((n.linear_feature_id IS NOT NULL)::int) AS n_at_fwa_base_measure,
       sum((n.linear_feature_id IS NULL)::int)     AS n_at_broken_measure
FROM fresh.streams f
LEFT JOIN whse_basemapping.fwa_stream_networks_sp n
  ON n.linear_feature_id = f.linear_feature_id
 AND n.downstream_route_measure = f.downstream_route_measure
WHERE f.watershed_group_code = 'BULK';
--> 87,639 | 30,046 at an FWA base measure | 57,593 at a broken measure
```

So a current-code job over legacy BULK ground would, under physical identity,
replace the 30,046 rows sitting at FWA's own measures and leave the 57,593
broken-measure rows behind as stale duplicates of the same ground. Under the
parent-segment key both go.

### E. Is a float equality safe in the DELETE predicate?

Yes, for the values in play, and the reason is not "floats compare fine":

- **Derived rows: 275 of 275 have an integral measure.** `frs_break_apply()` writes
  `round(b.downstream_route_measure::numeric, measure_precision)`
  (`R/frs_break.R:612`) and `frs_habitat()` passes `measure_precision = 0L`
  (`R/frs_habitat.R:232`). An integer below 2^53 converts to `double precision`
  exactly, so the stored value is exact and `=` is exact.
- **Base rows keep FWA's own double**, copied by `INSERT … SELECT` between two
  `double precision` columns with no cast — bit-for-bit, so `=` is exact. (123 of
  the job's 189 base measures are fractional, so this half matters.)
- **The cross-run risk is recomputation, not representation.** The predicate
  compares a measure this run computed against one a previous run stored. Measured
  directly: two runs of the same AOI into one target produced 464 rows and 464
  distinct `(linear_feature_id, downstream_route_measure)` pairs, each appearing
  exactly once — the second run reproduced the first's measures exactly and
  replaced rather than duplicated. But that is a property of break detection being
  deterministic for the same AOI, not of the key. A *different* AOI over the same
  ground can break at different measures, and then physical identity matches
  nothing and leaves stale rows (the parent-segment key does not have this
  failure).

So: safe, but it buys a predicate whose correctness rests on an extra premise the
parent-segment key does not need.

### F. The key does not transfer to #293, and that is a separate finding

Read #293 before writing any NEWS. Its targets carry **only** `id_segment` and
`watershed_group_code` as identity:

```
fresh.streams_habitat_co        : id_segment, watershed_group_code, accessible,
                                  spawning, rearing, lake_rearing, wetland_rearing
<current code>_habitat          : + species_code
```

No `linear_feature_id`, no `downstream_route_measure`. So neither physical
identity nor the parent-segment key can be used there without widening the
habitat schema or joining back through the working streams table. #293's own fix
— narrow the delete from whole groups to the job's own rows — can only be keyed
on the pair on that table.

And the pair is not sound there either, for exactly the reason in C: 81 of this
one job's derived ids equal a real same-group `linear_feature_id`, so a pair-key
delete on a habitat table built by current code can remove a legitimate
same-group row. **Narrowing the group set does not fix that**; it needs
`id_segment` to be unambiguous, or the habitat table to carry physical identity.
That is a widening question for #293, and it is not resolved by whichever key
#282 picks — contrary to the resume instruction's premise. Recorded here and
owed to #293's body.

## Phase 3-4, 2026-11-01

### Damage already in the wild: none attributable to #282

`data-raw/audit_persist_282.R` against `fresh.streams`, 98 groups:

| groups | with a shortfall | segments missing |
|---|---|---|
| 98 | 3 (LPCE, KETL, CHWK) | 34 |

All 34 are `edge_type` 6010 — "Construction Line, connectors (for streams that
leave and re-enter a watershed group)" (`inst/extdata/edge_types.csv:41`) — and
every one of their blue lines is present in the table. A shortfall that is
uniform by edge type with the blue line retained is a filter's signature, not row
loss; `R/frs_break.R:192` and `:314` exclude that edge type explicitly.

This agrees with Phase 0 rather than adding to it: the loss **cannot** have
happened on this table, because a current-code job's `id_segment` values are
`linear_feature_id`-scale and the table's are 1..n per group, so the broken
delete matches nothing there. The audit is kept for a table built by current
code, where the same query is the detector.

### lintr

| tree | lints |
|---|---|
| `origin/main` | 1400 |
| this branch | 1425 |

+25, every one `indentation_linter` on a continuation line, in the same style as
the code around it — the linter's hanging-indent rule is unmet across the package
(1400 pre-existing, 293 of them in the files this branch touches), so matching it
locally would make these lines inconsistent with their neighbours.
`CLAUDE.md`'s "Surgical Changes" prefers the neighbours. The three
non-`indentation_linter` lints in the touched files are all pre-existing
(`object_length_linter` on `.frs_validate_gradient_thresholds`, and a semicolon
and a long line in tests predating this branch).

Two `object_usage_linter` warnings — *"no visible global function definition for
`.frs_persist_streams`"* — appeared first and were the stale installed package,
exactly as `code-check-r.md` describes: `exists(".frs_persist_streams",
asNamespace("fresh"))` was `FALSE` against the installed 0.51.0. Both cleared
after `devtools::install()`, with no code change.

### Issue bodies reconciled

- **#282** — the body stated the wrong `id_segment` mechanism and proposed the
  pair key. Corrected in place, with the measured sections replacing "Not yet
  measured" and the superseded proposal struck rather than deleted.
- **#293** — the owner's call was to record the finding there. Its body now
  separates the scope defect it was filed for from the second defect measured
  here (`id_segment` ambiguity on a current-code table, 81 of 275 derived ids),
  states that its targets carry no `linear_feature_id` so #282's key is
  unavailable, and lays out (a) widen the schema, (b) key through the working
  table, (c) make `id_segment` unambiguous — undecided, which is right, since it
  is a stored-data decision.

### #295's question, as this release answers it

`NEWS.md` 0.46.0's wrong sentence is **not** rewritten. A changelog entry is
history; this release's entry carries the correction and points at
`research/id_segment_identity.md`. #295 stays open for #231's body, which is not
this branch's.

### Phase 4 item that is moot

"File the same-group `id_segment` key question, sibling of #218 — only if Phase 0
keeps the pair key." The owner chose the parent segment, so `to_streams` no
longer keys on `id_segment` at all and the question does not arise there. Where
it does arise is #293, and it is now option (c) in that body — so it is filed,
not dropped, and not duplicated into a new issue.

### Mutation sweep — the guards fire, measured

`dev/mutation_sweep.R dev/mutation_sweep_sites_persist_282.csv '^(frs_habitat|utils)$'`,
2026-11-01, against `f1f649b`'s code (the restructured single-decision-site
shape, not the pre-restructure one the discarded first sweep tested). Baseline
required 0 red / 0 skip; a site is credited only on red → green → red.

| site | file:line | red | caught |
|---|---|---|---|
| the defect itself — `if (in_to) return("linear_feature_id")` | `R/utils.R:1213` | 4 | yes |
| key-mismatch error | `R/utils.R:1206` | 1 | yes |
| WSG target needs the column | `R/utils.R:1192` | 1 | yes |
| no-key-at-all error | `R/utils.R:1216` | 1 | yes |
| target ≠ source guard | `R/utils.R:1244` | 1 | yes |
| WSG code quoted, not pasted | `R/utils.R:1255` | 1 | yes |
| "one fact derived twice" — the guard asks the chooser | `R/utils.R:1297` | 2 | yes |
| added-key NULL guard | `R/utils.R:1298` | 1 | yes |
| sequential path calls the helper | `R/frs_habitat.R:523` | 3 | yes |
| mirai path calls the helper | `R/frs_habitat.R:668` | 1 | yes |

**Sites with no test catching them: 0 of 10.** The two that matter most are the
last-but-three and the first: restoring the defect reddens four tests including
the #282 integration test, and substituting the chooser call in
`.frs_persist_streams()` with a hardcoded key — the regression `f1f649b`
removed — reddens two, so the property test that pins the two sites' agreement
is load-bearing rather than decorative.

### The mirai path, run rather than reasoned about

`workers = 2L` is not exercised by any test in the suite (no test file
mentions `workers`), and the daemon resolves fresh's internals in the
**installed** namespace, so a `load_all()` run proves nothing about it. Run
2026-11-01 against the installed branch, as the #282 scenario end to end:

```
run 1 rows: 464
decoy inserted, OTHR rows: 1
collision live (decoy id in run-2 ids): TRUE
OTHR rows after run 2: 1
run 2 own rows: 464 (run 1: 464)
id sets equal: TRUE
MIRAI 282 CHECK: PASS
```

Same six assertions as the sequential integration test, through
`R/frs_habitat.R:668`. Script: the scratch `mirai_282.R` reproduced here; it is
not committed, because a committed version would need a test harness that
installs the package first.

### The one NEWS figure quoted from the parked session, re-derived

`CLAUDE.md` requires a measured figure in NEWS to be re-derived at the time of
writing. The NEWS entry cites **259 blue lines spanning more than one watershed
group** as the context for #294.

```sql
SELECT count(*)::int FROM (
  SELECT blue_line_key FROM whse_basemapping.fwa_stream_networks_sp
  GROUP BY blue_line_key HAVING count(DISTINCT watershed_group_code) > 1) q;
--> 259   (re-derived 2026-11-01; 259 on 2026-10-28)
```

### Full suite

`devtools::test()` with `set_max_fails(Inf)`, 2026-11-01:
`[ FAIL 0 | WARN 21 | SKIP 6 | PASS 2501 ]`.

All 21 warnings are one sf message — *"Could not find a simple features
geometry column. Will return a `data.frame`."* — from
`test-frs_network_features-live.R` (3) and `-local.R` (18), neither touched by
this branch. The 6 skips are the `FRESH_FWAPG_TRIAL` gate (4) and the two
`bcfishpass`-schema `frs_params()` tests, which skip by design on a database
without that schema.

## Round 1 of `/code-check branch`, 2026-11-01

Five findings, two bugs. Both bugs were in code this branch added, and both were
reproduced here before being fixed.

### The added-key guard was a one-shot proxy

The guard refused a target whose key column *this call had added*. But
`.frs_persist_columns()` runs the `ALTER TABLE ... ADD COLUMN` before the guard
is reached, with no transaction around it, so the column is already on the
target permanently when the error is raised. Reproduced on
`working.gp_dst`, a target that predates `linear_feature_id` and holds one row:

```
run 1 : ERROR: working.gp_dst was missing linear_feature_id ...   dst = {NULL, 'stale'}
run 2 : OK                                 dst = {NULL,'stale'}, {42,'job'}
run 3 : OK                                 dst = {NULL,'stale'}, {42,'job'}
```

The error text says to re-run, and the re-run passes silently with neither
remedy applied. Worse than no guard, because it reads as handled.

"This call added the column" is a proxy for "the target holds rows whose key is
NULL", and the property is directly measurable on every call. The guard now asks
the target: `count(*) WHERE <key> IS NULL`, for whichever of the three keys the
job uses — so it also covers a NULL `linear_feature_id` or `id_segment` arriving
any other way, which the proxy never could. `cols_added` is still read, to say
in the message whether the column was just added. Cost measured on
`fresh.streams`, 3,802,814 rows: **1.43 s** for the count, against a persist that
already deletes and inserts thousands of rows.

The old tests dropped the target first, so only the cold path ran — which is why
the mutation sweep credited the guard as covered. Both calls are now asserted.

### `wsg` **and** `aoi` together is a subset job, and was overwriting the whole group

`frs_habitat()` accepts both. `R/frs_habitat.R:316-322` ANDs a character `aoi`
into the group filter, and for an `sf`/list `aoi` replaces the group predicate
altogether. Either way the job holds a *subset* of the group — and the spec
still carried `wsg = w`, so the persist deleted the whole group and inserted
back only the subset. Every row of that group outside the AOI was lost; with an
`sf` AOI the working table can also span groups, so rows of other groups were
inserted and never deleted, duplicating. Pre-existing, and the same shape as
#282 itself: a delete wider than the insert.

Three claims this branch had added were false for that mode, and the worst of
them was the repair instruction — "re-run the affected group with `wsg`" — since
narrowing a repair with an `aoi` is exactly when someone reaches for it, and it
would have made the damage larger.

Fixed at the decision, not at the claims: `.frs_partition_wsg(wsg, aoi)` returns
the group only when `aoi` is `NULL`, the spec carries it as `partition_wsg`
beside `wsg` (which the verbose print still uses), and both persist calls read
it. A subset job therefore keys on the parent segment like any other custom AOI,
which is correct for both sub-cases, including one spanning groups. The roxygen,
the `@param to_streams` entry and the NEWS line now say this.

### The partition overwrite is one statement

`code-check-infra.md`, "Two-statement DELETE/INSERT into a persist table is not
atomic". fresh#114 removed the known cause of a failing INSERT, but a
`statement_timeout`, a cancelled query or a dropped connection between the two
autocommitted statements still loses the partition — the same loss as #282,
reached another way. This branch created the single place where that is one fix.

A data-modifying CTE, `WITH del AS (<delete>) INSERT INTO ... SELECT ...`, runs
the delete exactly once and to completion against the statement's own snapshot,
so the insert's rows are invisible to it. One statement is atomic whether or not
the caller holds a transaction open, which `BEGIN`/`COMMIT` here would not be —
RPostgres refuses a nested `dbBegin()`. Verified on a scratch pair: replaces
rather than duplicates, leaves another group's row intact, and is idempotent
across runs.

The test for it forces the insert half to fail with a `NOT NULL` the source
violates. Restoring the two-statement form in a copy of the package reddens it
exactly as it should — `nrow(res)` 0 against 1, the partition deleted and not
written back — so the assertion discriminates rather than passing on both
shapes.

### Two smaller ones

- `data-raw/audit_persist_282.R` used `on.exit()` at a script's top level, which
  never fires (`code-check-r.md`), and the column check below it can `stop()`
  with the connection open. Now `withr::defer(..., envir = globalenv())`.
- `findings.md`, `task_plan.md` and `review-plan.md` all said the watershed-group
  predicate uses `IS NOT DISTINCT FROM`; the shipped statement is
  `watershed_group_code = '<code>'`. Behaviourally moot, since `wsg_code` cannot
  be NULL there, but the stale text was also the stated rationale for the guard
  that finding 1 showed to be one-shot, so the two are reconciled together: the
  NULL case is handled by a guard covering all three keys, not by the predicate.

### Not changed

The reviewer confirmed the custom-AOI key's premise independently —
`linear_feature_id` is globally unique in FWA (4,907,441 rows / 4,907,441
distinct) and 0 values span a watershed group — and found no injection surface,
no `sprintf()` placeholder mismatch, and `.frs_persist_columns()` with exactly
one non-test caller. The three accepted tradeoffs stand: `to_barriers` is #294,
the `indentation_linter` lints match their neighbours, and `NEWS.md` 0.46.0 is
history.

## Round 2 of `/code-check branch`, 2026-11-01

Three findings. The first is a defect **inside round 1's own fix**, which is the
pattern that keeps the review loop open: from here only an enumeration ends it,
not a quiet round.

### The data-modifying CTE was wrong, and `fresh.streams` is exactly where it breaks

Round 1 made the overwrite one statement,
`WITH del AS (<delete>) INSERT INTO <to> ... SELECT ... FROM <from>`. Every
sub-statement of a data-modifying CTE runs under **one command id**, so the
insert's uniqueness check still sees the rows the same statement's delete is
removing. The delete does run to completion — that part was right — but it
cannot free a key for the insert.

`fresh.streams` carries `CREATE UNIQUE INDEX streams_pkey ON fresh.streams
(id_segment, watershed_group_code)`, and so does every sibling schema's
`streams`. Reproduced on a target shaped the same way:

| form | key | run 1 | run 2 |
|---|---|---|---|
| CTE | `linear_feature_id` | OK | **duplicate key violates `ck_dst_pkey`** |
| CTE | `watershed_group_code` | OK | **duplicate key violates `ck_dst_pkey`** |
| two statements | `linear_feature_id` | OK | OK |

Both keys regress, the whole-group one included — and that is the key the
`@param to_streams` text and the NEWS entry name as **the repair** for a table
damaged by an earlier release. On a populated `fresh.streams` the repair would
have aborted.

**Why nothing on the branch caught it.** `.frs_persist_streams()` creates an
absent target with `CREATE TABLE IF NOT EXISTS ... AS SELECT * ... LIMIT 0`,
which copies no constraints. Every fixture — the three `.frs_persist_streams()`
tests, `working.persist_282_streams`, and the scratch pair this file cited as
having verified the CTE "idempotent across runs" — is therefore structurally
incapable of carrying a unique index, and an unkeyed target is idempotent under
both forms. Textbook `code-check.md`, "A fixture that cannot reach the failure
mode": the verification could not have disagreed with the code. The mutation
sweep shares the blind axis, since it mutates guards rather than the statement
form.

**What shipped instead.** One transaction, two statements — which is what
`code-check-infra.md` prescribed in the first place. Separate commands inside a
transaction do see each other, so the delete frees the key. `dbBegin()` refuses
a nested transaction (measured: `Nested transactions not supported.`), and a
caller who already holds one open has already made the pair atomic with respect
to their commit, so a failure to begin is not an error: begin if we can, roll
back on the way out unless we committed.

**The fixtures now carry a unique index**, as the real targets do, and one new
test re-runs the same ground three times under each key. Restoring the CTE in a
copy of the package reddens it — 5 failures, `duplicate key value violates
unique constraint "test_282_uniq_pkey"` — so the new fixture discriminates
where the old one could not.

One documentation claim went with it: "overwrites its own partition **before**
inserting, in one statement". A CTE's sub-statement order is explicitly
unpredictable, so that sentence was wrong on both halves; it now says one
transaction.

### `.frs_same_relation()` is a pre-filter, and its roxygen said it was exact

`.frs_validate_identifier()` admits an unqualified name, so `to_streams =
"streams_bulk"` against `working.streams_bulk` is one relation whenever
`working` is on the `search_path`, and the two strings compare unequal — the
self-delete guard passes and the target empties, since a delete whose subselect
reads the table it deletes from matches every row. Not reachable as this
database is configured (`search_path = public, whse_basemapping, usgs,
hydrosheds`, measured), and `search_path` is database state rather than
anything the package controls, so it is latent rather than live.

The string comparison stays where it is: it runs inside
`.frs_persist_delete_sql()`, which is a pure builder with no connection so that
the delete-key proof runs on CI. The exact test is now made in
`.frs_persist_streams()`, where both tables exist by then, by comparing their
`regclass`. The roxygen says which is which.

### The audit script compared counts where it needed a set difference

`n_missing` was `n_fwa - n_present`, with `n_fwa` counted under
`.frs_stream_guards()` and `n_present` counted without them. A
`linear_feature_id` in the table outside the guarded set therefore inflated
`n_present` and cancelled a segment that really was absent — in the column that
decides whether production data is damaged. `NOT EXISTS` against the guarded
set answers the question the header asks. The `LEFT JOIN` also ran from `fwa`,
dropping a group present in the table with no guarded FWA rows, so "Groups in
table" meant groups in FWA ∩ table; it now drives from the groups.

Re-derived on `fresh.streams` with the set difference, 2026-11-01: **98 groups,
3 with a shortfall, 34 segments**, LPCE 17 / KETL 11 / CHWK 6 — identical to the
count method, so nothing was masked in this table and the figure quoted above
stands. It is now derived the way that cannot mask.

### Confirmed clean by round 2

Round 1's other fixes were checked and hold: the NULL-key guard is correct for
all three keys and both the cold and warm paths (`cols_to` is the post-`ALTER`
union, so a just-added key is a legal key and the guard rather than the chooser
stops the run, and the message switches wording exactly when `cols_added`
empties); `.frs_partition_wsg()` is reached on every persisting path, and
`wsg_code` feeds nothing but `.frs_persist_streams()` at all four sites, so it
cannot change what `frs_extract()` or `frs_network_segment()` see;
`withr::defer(envir = globalenv())` is right and `withr`'s absence from
`Suggests` is harmless because `data-raw/` is `.Rbuildignore`d. `DELETE FROM`
occurs exactly twice in `R/frs_habitat.R`, both `blue_line_key`, so pinning that
count is a live tripwire.

## Round 3 of `/code-check branch`, 2026-11-01 — the mechanism, enumerated

Round 3 was asked for the **mechanism** behind rounds 1 and 2 and an
enumeration of what it implies, because round 2 found a defect inside round 1's
fix and the stopping rule then requires an enumeration rather than a quiet
round.

### The mechanism

**A property of the *code* stood in for a property of the *database*.** Every
finding so far is one instance, and in each the proxy was decidable from the
source alone — which is exactly why each survived into a live run:

| property wanted | predicate shipped |
|---|---|
| the target holds no row the delete cannot reach | *this call just added the key column* |
| the job covers every row of the group | `wsg = w`, the group the **call named** |
| delete + insert are one unit of work | *one SQL statement* |
| the insert sees the delete's effect | *a CTE is atomic, therefore sequential* |
| `to` is not `from` | `tolower(a) != tolower(b)` |
| the fixture has the target's shape | `CREATE TABLE ... LIMIT 0` |
| `n_missing` is the absent set | a difference of two differently-filtered counts |

Round 3 then found the same mechanism in two places the earlier fixes had not
reached, which is the enumeration earning its keep.

### Enumeration

| set | walked | verdict |
|---|---|---|
| guards / `stop()`s / decisions added or changed | 15 | 9 are the property; 5 are documented proxies, 4 of them sound; 1 was the property with **no test that could fail if removed** |
| test fixtures added | 8 | 3 carried the target's unique index; 0 carried geometry, generated columns, triggers, RLS or FKs; the integration fixture carried none |
| prose claims asserting a quantity, a universal or a behaviour | 14 | 8 supported, 4 **not** supported, 1 caveated, 1 incomplete |

### The bug it found: the audit's reference set names guards nothing applies

`frs_extract()` applies **no** guards — read it: `R/frs_extract.R:74-113` builds
its WHERE from `.frs_resolve_aoi()` and the caller's `where`, nothing else, and
`.frs_stream_guards()` is called only from the `frs_network*` and
`frs_stream_fetch` family. The `edge_type != 6010` predicates at
`R/frs_break.R:192` and `:314` sit inside the break-detection lookahead, not on
the write path. So a current-code run writes placeholder and unmapped segments
into `to_streams`, while the audit's reference set excluded them — and the
comment and NEWS both attributed those guards to `frs_extract()`.

Measured, `BULK`: 32,472 FWA segments, 30,046 passing the guards, **2,426
(7.5%) failing them**. A partition that had lost only guard-failing rows would
have reported `n_missing = 0`, and a healthy current-code partition would have
reported more rows in the table than in the reference set. The tool that decides
whether production data is damaged failed toward clean.

It now reports **both** reference sets, because which one is right depends on
who wrote the table and reporting one decides that for the reader. On
`fresh.streams`, 2026-11-01:

```
Groups in table: 98
Rows with a NULL watershed group (not auditable): 0
Against every FWA segment  — groups short: 98  segments: 151038
Against guarded segments   — groups short:  3  segments:     34
```

That pair is the whole answer. `n_in_table` equals `n_fwa_guarded` exactly, for
every group — so the legacy table was written by a pass that applied the
guards, and the 151,038 "missing" segments are that filter, not a loss. Against
the guarded set the shortfall is the same 34 as before, in LPCE (17), KETL (11)
and CHWK (6), and **all 34 are `edge_type` 6010**, re-checked on the guarded
subset alone. The earlier conclusion survives; the number it rested on now comes
from a reference set that says which generation it is about.

### The rest of round 3, each verified before acting

- **The `regclass` same-relation test had no test and no sweep row** — round
  2's own fix, unpinned. It now has both: a test that puts `working` on the
  `search_path` and passes the target as a bare `test_282_rc_src`, which names
  one relation with the source and compares unequal as a string, and two
  mutation sites.
- **`tryCatch(dbBegin, error = ) → FALSE` read every failure as nesting**,
  silently reverting to the autocommitted pair the transaction replaces — the
  round-1 shape again, inferring a condition from a failure. Only the nesting
  message proceeds now; anything else raises. Both branches have a test: one
  calls the helper inside a caller's open transaction, the other stubs
  `DBI::dbBegin` to a connection failure and asserts it raises with nothing
  written.
- **The NULL-key guard is scoped to the whole target, not the partition.** That
  is deliberate — a row with no key is one no run can ever address — but it has
  a consequence nothing said: a table gaining `linear_feature_id` is repaired
  one group at a time, and until every group has been re-run a custom-AOI run
  refuses the target. The error now names that escape ("finish the migration —
  re-run every group with `wsg` and no `aoi`"), and so do the roxygen and NEWS.
- **The `wsg` branch checked `cols_to` only** where the `linear_feature_id`
  branch checks both sides, for the reason the latter documents. Not reachable
  through `frs_habitat()` today; made symmetric, since the helper's contract is
  what the next caller reads.
- **`NEWS.md` still said the overwrite is "one statement"** — the design round 2
  removed, with `R/utils.R` four lines away saying "NOT one statement". Fixed.
- **"and so does every sibling schema's `streams`"** was a loose quantifier.
  Measured: **296** `streams` relations on the instance, **0 without a unique
  index** — 198 unique on `(id_segment)` alone and 98 on `(id_segment,
  watershed_group_code)`. Stronger than the claim, and the sharper fact is that
  the 198 keyed on `id_segment` alone would also have been broken by the CTE,
  whatever key the delete used. Round 3's own counter-claim, that
  `bcfishpass.streams` is the only other such table, is wrong; this is measured
  from `pg_indexes`.
- **`@param to_streams` said `wsg` + `aoi` "narrows the job to a subset of the
  group"**, which is false for an `sf`/list AOI: that arm replaces the group
  predicate, so the run can cover ground outside the group. The key chosen is
  right either way; the sentence now says both arms.
- **The integration fixture's target carried no constraints**, since the helper
  creates it with `CREATE TABLE ... AS SELECT * ... LIMIT 0`. It now gains the
  unique index the real tables carry, so the end-to-end test can also tell a
  correct overwrite from one whose delete does not free its key.

## Round 4 of `/code-check branch`, 2026-11-01 — the enumeration, re-walked

Round 4 re-walked the four candidate sets on the current tree and named four
gaps. All four are closed below. Counts are its, verified where they were
actionable.

| set | walked | verdict |
|---|---|---|
| guards / `stop()`s / decisions | **24** (arm granularity; round 3's own fix split one arm in two) | 22 are the property, 2 are declared proxies backed by the `regclass` test, 20 had a test that fails if removed, **2 arms had neither test nor a resolving sweep row** |
| test fixtures | 12 | unique index and NOT NULL now reachable; triggers, RLS, partitioning, generated columns, geometry/SRID constraints and defaults still not, and **none of them matters here** — the only database objects that change the outcome of `DELETE ... WHERE <key>` + `INSERT (cols) SELECT cols` are a unique index and a NOT NULL |
| prose claims | 26 | 24 supported, 1 on narrower evidence than the sentence names, **1 not supported for one of the three keys** |
| mutation-sweep rows | 14 | **13 resolved** |

### The bug: my own proof instrument could not run

Round 3 replaced the one-sided watershed-group column check with the two-sided
`lacking <- c(to, from)[!c(...)]` form and **did not update the sweep's site
list**. Row 3's pattern matches 0 lines of `R/utils.R` now (confirmed: 0
occurrences of the old text, 1 of the new), and the sweep validates every site
before it runs a test, so it refuses with exit 2 before the baseline — the
instrument for "restore the bug and prove the guard fires" could not be run on
the tree it ships with. It fails toward refuse, which is the right direction,
but the sweep result recorded earlier in this file is against `f1f649b` and
predates both the current code and four of the rows now in the list.

This is the inside-a-fix pattern for the third consecutive round: round 2 found
a defect in round 1's fix, round 3 in round 2's, round 4 in round 3's.

### The two untested arms, and why they were invisible

The `cols_from` arm of the watershed-group guard and the `cols_from` half of the
`id_segment` `&&` were each caught by nothing: round 4 measured that substituting
`"watershed_group_code" %in% cols_from` with `TRUE` leaves the filtered suite at
83 passes, 0 failures. Neither arm is reachable through `frs_habitat()` today —
its working table always carries both columns — so this was unproven coverage
rather than a live defect. It matters because the guard's stated purpose is the
helper's contract for the next caller, and without the arm that caller gets a
delete keyed on a column its `INSERT` cannot supply.

Five pure-string cases now cover both arms of both guards, including the
both-sides-lacking case, and two mutation rows address the arms directly.

### The circular remedy

The NULL-key guard's message offered "finish the migration — re-run every
watershed group with `wsg` and no `aoi`". That is right for the
`linear_feature_id` and `id_segment` keys: a whole-group run keys on
`watershed_group_code`, so NULL `linear_feature_id` rows do not block it and the
staged migration genuinely works. It is wrong when the NULL column **is**
`watershed_group_code` — every whole-group run then meets the same guard, so the
message sent the reader in a circle. The clause is now conditional on the key.
Unreachable on `fresh.streams`, whose `watershed_group_code` is `NOT NULL`.

### What round 4 confirmed by walking rather than assuming

All three earlier fixes hold on the current tree and are each pinned: the
NULL-key guard measures the target every call and is tested cold **and** warm
(three consecutive calls); the overwrite is two statements in one transaction
with a rollback on the way out, tested against a `NOT NULL` violation and
against three idempotent re-runs under both keys on a target carrying a unique
index; the `dbBegin` `tryCatch` matches only the nesting message, with both
branches tested. `.frs_persist_columns()`'s widened return was grepped across
`R/`, `tests/`, `data-raw/` and `dev/` — one production caller and three test
sites, all updated. The new explicit transaction takes only `RowExclusiveLock`,
with the `CREATE`/`ALTER` still autocommitted ahead of it, and concurrent
workers touch disjoint rows under either key, so `workers > 1` cannot deadlock
on the pair. Two load-bearing design facts were re-derived from code rather than
recalled: broken sub-segments keep the parent `linear_feature_id`
(`R/frs_break.R:683-688`, `sid = "id_segment"` from
`R/frs_network_segment.R:220`, so `linear_feature_id` lands in `cols_carry`),
and `.frs_add_id_segment()` sets base rows to `linear_feature_id`.

One scope correction it made, which I verified: `R/frs_feature_index.R` appears
in `git diff main...HEAD` only because this branch merged `origin/main` ahead of
`main`'s tip. The review range is the merge-base, `783c04c`, and that file is
0.52.0's work, not this branch's.

## Mutation sweep on the final shape — the enumeration's closing measurement

The sweep above is against `f1f649b` and is void: it predates rounds 1-4 and six
of the sixteen rows now in the site list, and round 4 found the committed list no
longer resolved at all. Re-run 2026-11-01 against `d1122e5`, the full 16 rows,
every site confirmed to resolve before the baseline, `'^(frs_habitat|utils)$'`:

| site | file:line | red | caught by |
|---|---|---|---|
| the defect itself — parent-segment key | `R/utils.R:1254` | 4 | #282 integration test + 3 |
| key-mismatch error | `R/utils.R:1247` | 1 | pure-string |
| WSG column required | `R/utils.R:1232` | 2 | pure-string × 2 |
| WSG column **both sides** (`cols_from` arm) | `R/utils.R:1231` | 1 | pure-string |
| `id_segment` **both sides** (`cols_from` arm) | `R/utils.R:1257` | 1 | pure-string |
| no key at all | `R/utils.R:1257` | 2 | pure-string × 2 |
| target ≠ source, by string | `R/utils.R:1285` | 2 | pure-string + `regclass` |
| target ≠ source, by `regclass` | `R/utils.R:1338` | 1 | live `search_path` test |
| only a nested txn skips the transaction | `R/utils.R:1423` | 1 | `dbBegin` failure test |
| WSG code quoted, not pasted | `R/utils.R:1296` | 1 | pure-string |
| the guard asks the chooser (one fact, once) | `R/utils.R:1361` | 5 | 5 live tests |
| NULL-key guard | `R/utils.R:1365` | 1 | warm-path NULL test |
| subset job is not a whole group | `R/utils.R:1180` | 1 | `.frs_partition_wsg` unit |
| habitat asks the partition decision | `R/frs_habitat.R:336` | 1 | enumeration test |
| sequential path uses the helper | `R/frs_habitat.R:535` | 3 | enumeration + #282 + #110 |
| mirai path uses the helper | `R/frs_habitat.R:680` | 1 | enumeration test |

**Sites with no test catching them: 0 of 16.** Baseline 0 red / 0 skip; a site is
credited only on red → green → red. The two arms round 4 found uncovered now
redden one test each, and the two rows round 4 added for them resolve.

This is what closes the review loop. Three consecutive rounds found a defect
inside the previous round's fix, so by `code-check.md`'s stopping rule a quiet
round could not end it — only an enumeration. Round 4's enumeration named four
candidate sets; the sweep is the measured verdict on two of them (24 guard sites,
16 sweep rows), the five added pure-string cases close the third gap, and the
conditional remedy clause closes the fourth. No round 5 was spawned: a fifth
reviewer could only re-assert what the sweep measures.

**Cost:** four reviewer agents over four rounds, three mutation sweeps (the first
discarded as superseded by the `.frs_persist_delete_key()` restructure, the
second stopped when round 2 exposed the CTE defect, the third above). Past the
`agent-operations.md` §2 bound of about five agents per task, which is reported to
the owner rather than used as a reason to have stopped at three.

### The closing runs, 2026-11-01

Against the reinstalled branch at `d1122e5` plus one lint fix:

| run | result |
|---|---|
| `devtools::test()`, full | FAIL 0 \| WARN 21 \| SKIP 6 \| PASS 2542 |
| `workers = 2L`, #282 scenario end to end | PASS, 6/6 assertions, 464 rows both runs |
| `lintr::lint_package()` | 1471 branch / **1400 `origin/main`** (worktree) |

The warning and skip counts are `main`'s and unchanged; the pass count rose from
2501 at the pre-review measurement, which is rounds 1-4's added tests.

The lint delta is +71, and all of it is on the branch's own files: 338 lints
there against 267 for the same files on `origin/main`. Broken down, +70 are
`indentation_linter`, of which this package carries 1400 before the branch — its
multi-line `sprintf()` SQL templates do not match lintr's expected continuation
indent, which is the house style `CLAUDE.md` describes and not something this
branch introduced. The remaining +1 was a `brace_linter` of mine
(`tests/testthat/test-utils.R:773`, a multi-line function body with no braces);
fixed, and the file is now at 0 brace lints. So no new lint class on the changed
files that `origin/main` does not already carry in kind.
