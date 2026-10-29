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
principles"), and a spyda-built network's column need not be, so the predicate
uses `IS NOT DISTINCT FROM`: `=` against a NULL matches nothing, which is the
silent-no-op direction.

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
