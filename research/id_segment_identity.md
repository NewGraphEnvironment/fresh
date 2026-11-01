# What `id_segment` is, and why the persisted table disagrees with the code

**Verified:** 2026-10-28 · **Issues:** #282 (found here), #218, #231, #277, #242 ·
**Produced by:** reading `R/utils.R` and `R/frs_break.R`, and four aggregates over
`fresh.streams` on the database `frs_db_conn()` reaches, with
`SET statement_timeout = 240000`

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
  artifact is being written.** Against a `fresh.streams`-era table the pair key
  confines a custom-AOI overwrite to its own group; against a freshly built table
  the residual collisions are same-group, and the pair key neither helps nor is
  safe to assume unique. `(linear_feature_id, downstream_route_measure)` is the
  physical identity of a sub-segment and was measured with 0 duplicates on a real
  working table (434 rows, 189 base / 245 derived). #282 carries that decision.

## How to re-derive

Run the four aggregates above against whichever table is in question — a working
table from `frs_network_segment()` and a persisted `to_streams` answer
differently, which is the whole point of this note. Set `statement_timeout`
first: a province-wide aggregate over `fwa_stream_networks_sp` times out on some
connections.
