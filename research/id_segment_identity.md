# What `id_segment` is, and why the persisted table disagrees with the code

**Verified:** 2026-11-22 for the barriers and NULL-group sections, 2026-11-02 for the rest ·
**Issues:** #282 (found here, and settled the delete key), #293 (widened the
sibling tables to the same key), #294 (barriers keyed the same way), #308 (a
NULL group refused), #277 (direct overlay held to the keys), #295, #218, #231,
#242 · **Produced by:** reading
`R/utils.R` and `R/frs_break.R`, four aggregates over `fresh.streams`, and the
Phase 0 measurements in `planning/archive/2026-11-issue-282-persist-delete-key/`,
all on the database `frs_db_conn()` reaches, with
`SET statement_timeout = 240000`, plus `data-raw/audit_habitat_293.R` for the
sibling tables' shapes and `data-raw/barrier_span_294.R` for persisted barriers

## The short version

`id_segment` is assigned in exactly two places, and they give it two different
meanings:

| site | applies to | value |
|---|---|---|
| `.frs_add_id_segment()`, `R/utils.R:571-577` | every row with a NULL `id_segment` | `linear_feature_id` — the FWA primary key, globally unique |
| `frs_break_apply()`, `R/frs_break.R:697-701` | only rows **created by breaking** | `(SELECT max(id_segment) FROM <table>) + row_number()` |

So under current code a segment that is never split keeps a globally unique id,
and only sub-segments get a derived one. `git log -L 571,578:R/utils.R` shows the
first has not changed since it was introduced (`0995567`, #84).

**The widely repeated claim that "each working table numbers its segments
independently", or "numbering restarts per job", describes neither site.** It is
in #282's body, in #231's "Shared mechanism", and in shipped `NEWS.md` 0.46.0
("each working table numbers its segments from `max(id_segment) + row_number()`").
Correcting those is tracked separately.

## But the persisted table is numbered per group, 1..n

Measured 2026-10-28 on `fresh.streams`:

```sql
SELECT count(*) n_rows, count(DISTINCT watershed_group_code) n_groups,
       sum((id_segment =  linear_feature_id)::int) n_base,
       sum((id_segment <> linear_feature_id)::int) n_derived
FROM fresh.streams;
--> 3,802,814 rows | 98 groups | n_base = 0 | n_derived = 3,802,814
```

```sql
SELECT watershed_group_code, count(*) n, min(id_segment), max(id_segment),
       min(linear_feature_id), max(linear_feature_id)
FROM fresh.streams WHERE watershed_group_code IN ('BULK','COTR') GROUP BY 1;
--> BULK  87,639 rows  id 1..87,639   lfid 17,000,014..868,144,543
--> COTR  36,815 rows  id 1..36,815   lfid 700,821,184..868,144,477
```

```sql
SELECT count(*) FROM (SELECT id_segment FROM fresh.streams
  GROUP BY id_segment HAVING count(DISTINCT watershed_group_code) > 1) z;
--> 113,305 id_segment values appear in more than one group

SELECT count(*) FROM (SELECT id_segment, watershed_group_code FROM fresh.streams
  GROUP BY 1,2 HAVING count(*) > 1) z;
--> 0 duplicate (id_segment, watershed_group_code) pairs
```

`id_segment` there is a **per-group 1..n sequence**, with not one row equal to its
`linear_feature_id`, and every one of COTR's 36,815 ids also present in another
group. That is what #218 measured (187 Naver Creek segments matching 22 groups),
and it is why joining on `id_segment` alone multiplies rows.

Current code cannot produce a per-group 1..n sequence, so `fresh.streams` was
written by an earlier pipeline — the `frs_habitat_partition` /
`frs_habitat_species` era, since removed.

## Why the distinction matters

Both statements are true of different artifacts, and a rule written from one of
them is wrong about the other:

- **`id_segment` is not safe to join on alone**, against either artifact. Against
  `fresh.streams` it collides across groups wholesale; against a freshly built
  table the derived ids collide with real `linear_feature_id`s elsewhere in the
  province. `(id_segment, watershed_group_code)` is the key to join on, and it
  currently holds on `fresh.streams` with 0 duplicate pairs.
- **`(id_segment, watershed_group_code)` is not stable across runs** of a freshly
  built table. The derived ids depend on `max(id_segment)` within the working
  table, so a different AOI over the same ground numbers its sub-segments
  differently.
- **Which delete key is correct for a partition overwrite depends on which
  artifact is being written** — and the answer is neither of the two keys #282
  first proposed. Against a `fresh.streams`-era table the pair key confines a
  custom-AOI overwrite to its own group; against a freshly built table the
  residual collisions are **same-group**, so it neither helps nor is safe to
  assume unique: of one run's 275 derived ids, 81 each equalled a real
  `linear_feature_id` in the run's own watershed group and **0** fell in another
  group. `(linear_feature_id, downstream_route_measure)` is the physical identity
  of a sub-segment and was measured with 0 duplicates on a real working table
  (434 rows, 189 base / 245 derived), and a float equality on the measure is
  exact here — derived measures are integral and base measures are copied
  `double precision` to `double precision` — but it rests on break detection
  reproducing the same measures, which a key that never names one does not need.

## The key that shipped: the parent segment

`fresh` 0.53.0 overwrites a custom AOI's partition of `to_streams` by
**`linear_feature_id`**, the parent FWA segment, and it is the only candidate
correct against both artifacts. Three measured facts decide it:

- **An AOI is a row predicate, never a cut.** Every arm of `.frs_resolve_aoi()`
  (`R/utils.R`) returns a WHERE clause, so a job holds whole FWA segments; nothing
  in the extract clips geometry at the AOI boundary. Breaking subdivides those
  segments *within* the run, so deleting the target's rows for a parent and
  inserting the run's own is a complete replace of the ground it covers.
- **No `linear_feature_id` spans a watershed group** — 0, measured across
  `whse_basemapping.fwa_stream_networks_sp` — so the overwrite cannot reach
  another group whatever the AOI covers. This is the property the `id_segment`
  keys lack, and it does not depend on which pipeline wrote the table.
- **It is the only key that clears stale sub-segments.** A re-run at different
  break measures leaves the previous run's sub-segments behind under either
  `id_segment` key; keying on the parent removes them.

`id_segment` remains the key only where neither table carries
`linear_feature_id` — a network that is not the FWA. One table carrying it while
the other does not is an error naming the table to migrate, not a silent fall
back to a key measured wrong.

**The sibling tables were widened to use it, in #293.** Before 0.54.0
`frs_habitat_classify()`'s and `frs_near_river()`'s targets carried only
`id_segment` and `watershed_group_code` (measured 2026-11-02: 221 habitat tables
and 114 `near_river` tables on the shared instance, **0** with
`linear_feature_id`; the table counts move as other work creates schemas, the
`0` does not), so
neither the parent segment nor physical identity was available there. #293 adds
`linear_feature_id` to both, **when the streams table carries one**, and keys
their partition delete on it through the same chooser.

Two things that fix only became safe once the reads changed with it:

- **The whole-group delete was what made `(id_segment, watershed_group_code)` a
  sound read key on a shared table.** After a job ran, the table held no other
  job's rows for that job's groups. Scoping the delete to the ground the job
  reinserts ends that: a whole-group run followed by a custom-AOI run **in the
  same group** — the repair path this note recommends — leaves two jobs' rows in
  one group, with ids derived independently. The 81-of-275 same-group collision
  above is what that costs. Every habitat-to-streams match in fresh therefore
  goes through one builder, `.frs_key_match()`, which adds the parent segment
  where both tables carry it; an enumeration test over the parsed functions
  fails on any site that spells a join inline.
- **The column cannot be unconditional.** `frs_habitat_classify()` does not
  require `linear_feature_id` and a test builds a streams table without one, so
  creating it on the target regardless would make the chooser's
  one-sided-mismatch error fire for every network that is not the FWA. The
  target gets the column only when the source has it, and the `id_segment`
  branch stays reachable for the rest.

**What #293 did not fix.** A species' rows that no later custom-AOI run
classifies are not removed by one, because a custom-AOI delete is scoped to the
species it writes. Those rows keep an `id_segment` from the numbering of the run
that wrote them, so within a parent segment they are ambiguous until a
whole-group run (`wsg_code` set) of their group replaces every species' rows. Adding the parent narrowed this from "wrong parent" to "ambiguous inside
one parent"; closing it is the `id_segment`-at-assignment work, the sibling of
#218, tracked in #300.

## Two things that make a persisted streams table unforgiving

Both measured while #282 was fixed, and both are properties of the database that
no reading of the source reveals:

- **Every persisted `streams` table has a unique index to violate.** 296 `streams`
  relations measured across the instance's schemas, **0** without one (198 on
  `id_segment` alone, 98 on the pair). `CREATE TABLE ... LIMIT 0` copies no
  constraints, so a test fixture built that way cannot reach the failure mode a
  real target reaches — a fixture needs the index added explicitly.
- **A data-modifying CTE is not an atomic overwrite.** All sub-statements of
  `WITH del AS (DELETE ...) INSERT ...` run under one snapshot and one command id,
  so the INSERT's uniqueness check still sees the rows the DELETE is removing:
  measured on a keyed target, run 1 succeeded and run 2 raised a duplicate-key
  violation, under both candidate keys. The overwrite is one **transaction** with
  two statements instead.

## Persisted barriers: the same key, for a different reason

Before #294, `frs_habitat(to_barriers =)` deleted by `blue_line_key` and reinserted the job's
barriers. That looked like the cross-group loss #282 fixed, but it was not one:
`frs_break_find()`'s multiclass arm takes the blue lines from the job's extract
and then reads **every** segment of those lines from `fwa_stream_networks_sp`,
with no group filter. A job's barriers therefore cover the whole line, the
neighbouring group's part included, and the blue-line delete matched exactly what
the insert wrote back.

What differs between two groups' jobs is the gradient classes, which come from
each group's species thresholds. So the last job to run on a line owned every
group's barriers on it, at its own classes. Measured 2026-11-22 on the `docker/`
fwapg: 157 mainstem lines span groups (the default `blk_filter` samples
mainstems; the issue's 259 counts every line), 108 of them join groups with
different thresholds, and on 5 of 12 sampled lines the second group's run changed
the first group's barriers, 41 of 126 positions
(`data-raw/logs/barrier_span_294/`).

Widening the key to `(blue_line_key, watershed_group_code)` would not have
helped, because the job would still delete and rewrite both groups' rows. Each
barrier now carries the `linear_feature_id` and `watershed_group_code` of the
segment it falls on, and a job deletes and inserts only the barriers on its own
segments (`.frs_persist_barriers()`), keyed by `linear_feature_id` like
`to_streams`. Two consequences: barriers on the rest of a line are written only
by the job that covers that part, and a barrier the finder rounds to 0.01 m right
on a group boundary can be keyed to the neighbour's segment.

The parent is found against each segment's top taken from the **next** segment's
start, not `upstream_route_measure`, which in the FWA can stop millimetres short
of it (510 gaps over 1 mm in BULK). A barrier rounded into such a gap matched no
segment under the plain bound and would have dropped out of the table: 39 of
104,550 barriers in BULK, 27 of 68,270 in MORR and 41 of 52,430 in LFRA
(code-check round 1, #318). The 12-line sample above, at those rates, would be
expected to find about 0.1, which is why it found none.

## A NULL group is refused, not read as a group

Since #308: every read that matches a habitat or `near_river` row to its segment equates
`watershed_group_code` (`.frs_key_match()`, `.frs_near_river_sql()`, the species
lookup in `frs_cluster()`). `NULL = NULL` is not true, so on a network whose
segments have no group the rows were written, and after #293 replaced correctly,
but never read. `IS NOT DISTINCT FROM` would make NULL act as one group but
cannot be a hash or index join key. So `.frs_group_required()` refuses any NULL
group, at every exported function that reads or writes habitat rows against a
streams table; `test-habitat_partition_293.R` walks the namespace call graph to
keep it that way. A network with no groups sets one constant value.

The same reasoning holds `frs_habitat_overlay()`'s direct mode to the keys: a
`by` holding `id_segment` must also name `watershed_group_code` when the target
carries it, and `linear_feature_id` when both tables do (#277).

## How to re-derive

Run the four aggregates above against whichever table is in question — a working
table from `frs_network_segment()` and a persisted `to_streams` answer
differently, which is the whole point of this note. Set `statement_timeout`
first: a province-wide aggregate over `fwa_stream_networks_sp` times out on some
connections.
