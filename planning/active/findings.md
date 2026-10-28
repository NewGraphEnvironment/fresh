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

## Resume, 2026-10-28: the live test's fixture

The whole stream network as `features` is the densest feature table there is. With the
new form on VICT (temp table of 2,147 segments), the prefilter admits **209,987** segments,
almost all through the wscode arm (segments whose wscode equals a VICT ancestor), and the
walk probes the temp table once per admitted feature: 43.3 s, against 92.8 s for the plain
join. Same digest (`4ab773e1ddeb9e316d03f987dcc9125e`, 1,597 segments with a feature).

Every 25th segment province-wide (`linear_feature_id % 25 = 0`, 195,875 rows, indexed and
analyzed like a feature table): new 1.7 s, plain 2.3 s, same digest
(`74bb945034718735fed79a0f7294e38f`, 535 segments, 980 pairs). The live test uses that.
It also showed `CREATE TEMP TABLE pg_temp.<name>` is accepted on PostgreSQL 17.5.

### Which arm a fixture can see (mutation runs, same day)

Removing each part of the new SQL in turn, against the live test:

| mutation | VICT | LKEL | UPET | SKGT |
|---|---|---|---|---|
| no blue-line arm (`OR false`) | passed | 6 fail | 6 fail | 6 fail |
| no ancestor arm (self code only) | passed | passed | passed | 2 fail |
| no `DROP` | 3 fail | – | – | 3 fail |

- The blue-line arm is redundant on FWA's own codes: **no FWA blue line carries two wscodes**
  (counted over `fwa_stream_networks_sp`, 0 rows), so the self-code arm already admits every
  feature on an AOI blue line. It matters for a feature table whose codes are missing or differ
  from the network's: `fwa_downstream()` returns a feature on the segment's blue line downstream
  of it with NULL codes (`fwa_downstream(1, 100, '100.1', '100.1', 1, 50, NULL, NULL, false, 1)`
  is true). The fixture adds NULL-coded copies of every 7th AOI segment to reach it.
- The ancestor arm matters only when an ancestor code is not also one of the AOI's own codes
  and the answer reaches a feature on it. LKEL contains Skeena main-stem segments (`400`);
  UPET has one ancestor outside (`200.692231`) but no answer pair on it. Answer pairs only
  that arm admits, every 25th segment as features: CHWK 0, SAHD 0, UPET 0, SKGT 22 of 40,495,
  GUIC 344,635 of 381,522, LPRO 153,072 of 217,443, MUSK 1.27 M of 1.31 M, UTRE 1.00 M of 1.05 M.
- The live test therefore uses **SKGT** (6,935 segments; one of them, a 30 m connector, `linear_feature_id` 868144510, is coded
  `100.111269`, so its ancestor `100`, the Fraser, has no
  SKGT segment): 6 s for both `include_equivalents` values and their plain-join references.

## Phase 3 measurement, 2026-10-28 (19:40-20:57 UTC)

`data-raw/network_features_prefilter.R SALR LKEL CHWK LSKE` on the local Docker fwapg,
no other client backend active; log and table in `data-raw/logs/network_features_272/`.
56 rows: 4 groups × 3 views × 4 runs, plus 8 `old_scoped` oracle runs.

- **The old SQL timed out (> 600 s) on every CH and BT walk** in all four groups on the
  province-wide `fresh_default.streams` + `aoi` shape. The new form took 0.34-8.35 s
  (DDL included), so > 72× (LSKE CH) to > 1,775× (LKEL BT).
- **Anthropogenic view (0.5 M rows):** old 0.85-4.51 s, new 0.17-1.74 s, 2.6-4.9×.
- **Against link's shape** (`old_scoped`: the same old SQL on an indexed temp copy of the
  group): 7.3-96.4 s, so the new form is 7.9× (LSKE) to 33× (CHWK BT) faster still. That
  isolates the prefilter's share, since both have the scoped table.
- **DDL:** 0.07-0.15 s for 7-14 k segments, 0.7 s for LSKE's 77,496.
- **Answers:** `d_set` agrees across every form of all 12 walks. `d_order` differs between
  `old_scoped` and `new` on SALR CH and CHWK CH/BT, the tie order the new `ORDER BY` key
  now fixes.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `$TMPDIR` unset in the Bash tool: `cat > "$TMPDIR/x.sql"` wrote to `/x.sql` (read-only) | Write scratch files to the session scratchpad path in full |
