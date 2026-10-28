# Findings — frs_network_features(): every walk probes the segments once per feature in the province (#272)

## Issue context

## What happens

`frs_network_features()` (fresh@v0.43.0; the SQL is unchanged since v0.29.0) joins the
AOI's segments to the whole feature table on `fwa_downstream()`. The planner drives from
the feature side and probes the segments once per feature, through a `BitmapOr` on
`blue_line_key` and `wscode_ltree <@ b.wscode_ltree`. With a province-wide table that is one
probe per feature in the table, whatever the AOI: 7.24 M for link's CH view, 3.48 M for
its BT view, 0.50 M for its crossings. The cost per feature depends on the AOI's segments
(their wscode GiST): 1.8 µs per feature for SALR, 10.3 µs for CHWK, 21 µs for LFRA (groups owning
main-stem segments are among the dearest).

Measured by NewGraphEnvironment/link#261 on a 241-group `default` build
(evidence in NewGraphEnvironment/link#393: `data-raw/logs/recompute_cost_261/`, verdict in `research/recompute_cost.md`): these walks
are most of link's post-consolidate recompute, and a per-group walk timing predicts its
minutes at Spearman 0.982.

## What a prefilter does

`fwa_downstream()` can only return a feature on one of the AOI's blue lines (criterion 1)
or whose wscode is an ancestor of, or equal to, an AOI segment's wscode (criterion 2,
`wscode_a <@ wscode_b`). Cutting the feature side to those first, through the feature table's own indexes (GiST on wscode, btree on blue line):

```sql
INNER JOIN (
  SELECT * FROM <features> f
  WHERE f.wscode_ltree = ANY (ARRAY(
          SELECT DISTINCT subpath(wscode_ltree, 0, k)
          FROM <segments>, generate_series(1, nlevel(wscode_ltree)) k))
     OR f.blue_line_key = ANY (ARRAY(SELECT DISTINCT blue_line_key FROM <segments>))
) b ON <the same fwa_downstream() predicate>
```

Over nine groups and 32 walks, it returns the same features per segment in every one, and
a group's walks run 3.6× (SPAT) to 24.6× (CHWK, 219 s → 8.9 s) faster in total. SETN gains 1.2×: its
cost is output (4.83 M pairs). Estimated over the provincial pool: 36 to 51 % of the
recompute's summed job time.

`IN (SELECT …)` in place of `= ANY (ARRAY(…))` still reads the whole table (SALR CH 6.1 s
against 2.9 s; `walk_prefilter_in_select.tsv`).

## One smaller thing seen

- The `ORDER BY` (wscode, localcode, measure, all descending) ties for co-located
  features, so their order in an array follows the plan. A unique last key (the feature
  id) would fix it. In four of 32 walks the order changed with the plan.

## Proposed

Apply the prefilter inside `frs_network_features()` for `direction = "downstream"`. The answer is unchanged apart from the tie order above.

Build the cut from the AOI's own segments, not from a watershed group's outlet (`frs_wsg_outlets()`, as `lnk_wsg_downstream_check()` uses for dams). Most of a walk's features sit inside the AOI above its outlet, and a watershed group can hold several drainages: in NewGraphEnvironment/link#374 an outlet-based closure missed readers in 150 of 241 groups. The ancestor-or-equal codes of every segment, plus their blue lines, cover both of `fwa_downstream()`'s criteria by construction.

Relates to #265 (which walk fresh uses); this keeps the predicate as it is.


## Exploration, 2026-10-28 (plan mode, read-only probes on the local Docker fwapg)

Scratch SQL: `probe_272*.sql` in the session scratchpad (not committed). Every number
below is a single shot, so cache state is in it: the sent LKEL streams-as-features walk
read 76 s under `EXPLAIN (ANALYZE, BUFFERS)` cold and 15 s warm. Phase 3 interleaves.

### The criteria, from fwapg's `db/schema.sql`

The 11-argument `FWA_Downstream()` body (which both the 10-argument wrappers call) returns
true only when `blue_line_key_a = blue_line_key_b` (criterion 1, with the measure test) or
`wscode_ltree_a <@ wscode_ltree_b` (criterion 2, with the localcode tests). So a feature `b`
can be downstream of an AOI segment `a` only if it is on one of the AOI's blue lines or its
wscode is an ancestor of, or equal to, an AOI segment's wscode. The prefilter admits exactly
that union, so it is a superset of every answer by construction; `include_equivalents` and
the tolerance change neither criterion's reach.

### Where the time goes: the planner, not the predicate

- Sent form, `fresh_default.streams` + `aoi = 'SALR'`, anthropogenic view (0.5 M): 2.5 s.
  Plan is segment-driven (parallel index scan on `streams_pkey` by WSG, then a `BitmapOr`
  of `barriers_blk_drm_idx` and `barriers_wscode_gist_idx` per segment). The GiST `@>`
  arm is **estimated at 77,961 rows per probe, actual 314**.
- Sent form, same segments, CH view (3.66 M): **> 240 s, timed out.** The 78k-per-probe
  estimate times 27,150 estimated segments drives the planner off the segment-driven plan.
- Issue's prefilter form (uncorrelated `= ANY (ARRAY(SELECT …))` subqueries) on the same
  segments, anthropogenic: 2.9 s. Plan: InitPlans for the two arrays, then
  `Nested Loop` with the admitted features `Materialize`d (estimated 107 rows, actual
  1,303) and the whole `fwa_downstream()` as a **Join Filter**: 11,392 × 1,303 =
  `Rows Removed by Join Filter: 14,833,619`. Same form on `fwa_stream_networks_sp` as both
  sides, LKEL: > 180 s (2,382 segments × 214,852 admitted features).
- link's `walk_prefilter.R` got its 3.6× to 24.6× with the group's segments in an indexed,
  `ANALYZE`d temp table (`zz_walk_streams`), which is also what `lnk_access()` does in
  production (`R/lnk_access.R`: "as a real TABLE (with indexes + ANALYZE), NOT a view …
  if the planner picks the ~800k-row barriers as the outer driver … cost explodes"). With
  a small indexed segments relation the planner drives from the admitted features and
  probes the temp table; with an 11.3 M-row `segments` and an `aoi` filter, probing it by
  `<@ '300'` would return a basin, so it falls back to the cartesian above.

### Forms tried, same digests everywhere

| form | SALR anthrop., province-wide | SALR CH, province-wide | LKEL streams-as-features | SALR CH, temp-table shape |
|---|---|---|---|---|
| sent | 2.5 s (1.15 s warm) | > 240 s | 76 s cold / 15 s warm | 16.4 s (link) |
| issue's uncorrelated prefilter | 2.9 s | – | > 180 s | 2.9 s (link) |
| E: correlated `= ANY(ARRAY(SELECT subpath(a.wscode,0,k)…)) OR blk = a.blk` as join cond | 4.3 s | 6.1 s | 56 s | 5.4 s |
| F: E inside a `CROSS JOIN LATERAL (… OFFSET 0)` fence | 2.7 s | 8.1 s | 52 s | 7.6 s |
| equi-join UNION (blk arm ∪ `subpath` arm, hash/merge) | 1.6 s | 20 s | – | – |

Digests (`md5` of `id:sorted array` over all segments): SALR anthropogenic
`1ce93d0bf1c5c958af276f952fa1fa51` and SALR CH `124ce29267bc8676d22c05c693b3182d` in every
form, equal to link's `walk_prefilter.tsv` `d_set` for the same walks; LKEL streams-as-features
`404422702e011f83a0a87b7081cbaa7e` for sent, E and F. E and F keep the planner segment-driven
in both shapes (E still builds the old GiST `@>` bitmap and `BitmapAnd`s it; F cannot use it)
but re-fetch each candidate feature once per segment, where the issue's form reads the
admitted set once and probes the small table. Hence the gate decision: the issue's form,
with the AOI's segments materialized by fresh itself.

### Local Docker fixtures for a live test

`whse_basemapping.fwa_obstructions_sp` carries `route_measure`, not
`downstream_route_measure`, so it cannot be a `features` table as the function stands.
`fwa_stream_networks_sp` as both sides works on any fwapg (`linear_feature_id` on both).
Segment counts: LKEL 2,382; SALR 9,384; ADMS 11,520. Pick a smaller group in Phase 1.
`bcfishobs.observations` (376 k, `wscode`/`localcode` unsuffixed) has only its pkey index.

### Related, out of scope

`frs_aggregate`, `frs_classify`, `frs_cluster`, `frs_feature_index`, `frs_habitat`,
`frs_network*`, `frs_waterbody_network`, `frs_wsg_drainage` and `utils.R` also call
`fwa_downstream()` (#265 lists the call sites). This issue keeps the predicate and touches
only `frs_network_features()`.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `$TMPDIR` unset in the Bash tool: `cat > "$TMPDIR/x.sql"` wrote to `/x.sql` (read-only) | Write scratch files to the session scratchpad path in full |
