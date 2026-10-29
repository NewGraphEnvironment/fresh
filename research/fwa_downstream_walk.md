# Walking FWA downstream: what `FWA_Downstream()` and the working table give a walk

**Verified:** 2026-10-21 on local fwapg (`whse_basemapping`), BULK working table from `frs_network_segment()`; "Prefiltering the feature side" 2026-10-28 and "Existence walks" 2026-10-29, local fwapg with link's `fresh_default` barrier views · **Issues:** #259, #272, #281 · **Produced by:** `data-raw/near_river_check.R` (logs `data-raw/logs/near_river_259/`), probes in `planning/archive/2026-10-issue-259-near-river/` (findings and review rounds 1 to 6); `data-raw/network_features_prefilter.R` (logs `data-raw/logs/network_features_272/`), probes and mutation runs in `planning/archive/2026-10-issue-272-network-features-prefilter/`; `data-raw/network_features_exists.R` (logs `data-raw/logs/network_features_exists_281/`).

A downstream walk that joins rows with `FWA_Downstream()` and sorts them `wscode_ltree DESC, downstream_route_measure DESC` reads as one contiguous chain from the origin. It is not one, in five ways. `frs_near_river()` handles each; any new walk should too.

## `FWA_Downstream()` (11-argument body)

- **Its `wscode_b = localcode_b AND wscode_a != wscode_b` branch never reads the origin's local code.** An origin with no local code is joined to the bottom row of every ancestor line, skipping the network between. Start a walk only from rows with a local code.
- **Its local-code branch does not require a different blue line.** A row on the origin's own line whose local code is out of step with its measure is accepted though it lies upstream (BULK segment 17012154: measure 4,595 m, above an origin at 2,760 m). On one line, let the measure decide.
- **Main-flow rows whose local code nests under a tributary's code** (`…415251.700137.023161` on the `…415251` line) are accepted as downstream of that tributary wherever they lie, so the path detours. 1 such row in BULK; 2,013 main-flow rows province-wide.
- **The confluence is where the tributary's local code puts it**, not where the lines meet. A walk entering at the first returned row can differ from one entering at the nearest point either way (BULK: longer in most cases, shorter by 14 to 67 m in 6 of 2,462 sampled).
- `subltree()` past the end of a code truncates rather than erroring, so mixed-depth comparisons do not fail.

## What the working table holds

- **`frs_network_segment()` keeps side-line rows with no local code and drops main-flow ones.** BULK: 2,426 rows with no local code, all side lines or `999.*` placeholders. Side channels: 238 of 358 edge-1100 rows in BULK, 50,280 of 83,642 province-wide (raw FWA).
- **About a third of connectors are side lines** (BULK: 574 of 1,624 edge 1450), which a main-flow walk drops; the path jumps from a tributary's mouth to the river's centreline. All BULK connector rows lie wholly inside the polygon whose `waterbody_key` they carry.
- **A group's table can leave and re-enter a river's course**, so a path jumps across a stretch outside the group (17.8 km in one BULK case). Gaps between consecutive path rows must be counted, not ignored.
- **A tributary can meet its parent part-way along a row.** Count only the part of that row below the meeting point (`ST_LineLocatePoint()`).

## Prefiltering a walk by straight-line distance

A `ST_DWithin(t.geom, o.geom, R)` prefilter is safe on a contiguous path (a dropped row is beyond R, and so is everything after it), but a jump can carry the path from a dropped row back within R. Checking the row directly above each kept row on its own line catches most cases; a dropped run that ends its line, or a row above that is out of step with its local code, escapes it. Walk each distance on its own so no answer depends on another's prefilter.

## Prefiltering the feature side

`frs_network_features(direction = "downstream", aoi = )` joins the AOI's segments to a
feature table on `fwa_downstream()`. Against a province-wide feature table, the cost is
in how the planner orders the join, not in the predicate. Two steps fix it, and both are
needed.

**What a feature must satisfy to be downstream.** The 11-argument `FWA_Downstream()` body is
true only when the feature is on the segment's blue line (criterion 1, plus the measure test)
or its wscode is an ancestor of, or equal to, the segment's (criterion 2,
`wscode_a <@ wscode_b`, plus the local-code tests). Admitting only features on one of the
AOI's blue lines, or whose wscode equals some `subpath(<segment wscode>, 0, k)`, is therefore
a superset of every answer. `include_equivalents` and the tolerance change neither criterion's
reach. On FWA's own codes the blue-line arm is redundant, because no FWA blue line carries two
wscodes (0 rows in `fwa_stream_networks_sp`). It keeps the answer right for a feature table
whose codes are missing or differ from the network's: `fwa_downstream()` accepts a feature on
the segment's blue line with NULL codes. The wscode arm admits the AOI's own codes and their
strict ancestors. The strict ancestors matter only where an answer reaches a code that is not
one of the AOI's own. The answer pairs only they admit (a feature on neither an AOI blue line
nor an AOI code; every 25th FWA segment as features, `include_equivalents = FALSE`) are 0 in
CHWK, SAHD and UPET, 22 of 40,495 in SKGT, and 1.00 M of 1.05 M in UTRE. So a test that cuts
an arm, or the wscode arm back to the AOI's own codes, needs a group and a feature table that
reach it: the local live test uses SKGT, plus NULL-coded copies of SKGT segments.

**Why the planner needs the segments in a small table.** With `segments` a province-wide
table filtered by `aoi`, the GiST `@>` probe of the feature table is estimated at 77,961 rows
per segment and returns about 314 (SALR, anthropogenic view). On the CH view that estimate
pushes the planner off the segment-driven plan, and the walk does not finish in 10 minutes. A
set prefilter alone does not help on that shape. The planner materialises the admitted
features and cross-loops them with the segments, with all of `fwa_downstream()` as a join
filter (SALR anthropogenic: 14.8 M rows removed). With the streams network as features (LKEL),
it does not finish in 3 minutes. What works is what link measured in link#261 and
`lnk_access()` does in production: the AOI's segments in a session temp table, with a btree
on `blue_line_key`, GiST on both codes, and `ANALYZE`. The planner then reads the admitted
features once and probes the small table per feature. The temp table costs 0.07-0.15 s for
7-14 k segments and 0.7 s for 77 k.

A read-only alternative was tried and rejected: a per-segment prefilter fenced in a
`CROSS JOIN LATERAL (… OFFSET 0)`. It keeps the plan segment-driven on any shape (8 s on SALR CH
province-wide, against more than 240 s sent) and returns the same answer. But it fetches each
candidate feature once per segment, not once overall, so on link's temp-table shape it took
7.6 s against 2.9 s.

**Measured** (`data-raw/logs/network_features_272/`; `fresh_default.streams` with `aoi`;
link's barrier views; old, new, new, old; mean of the two new runs, DDL included):

| group (segments) | CH: v0.44.0 / scoped only / new | BT: v0.44.0 / scoped only / new | anthropogenic: v0.44.0 / new |
|---|---|---|---|
| SALR (11,392) | > 600 / 17.2 / 1.94 s | > 600 / 8.1 / 0.80 s | 1.11 / 0.32 s |
| LKEL (7,448) | > 600 / 12.8 / 0.68 s | > 600 / 7.3 / 0.34 s | 0.85 / 0.17 s |
| CHWK (14,347) | > 600 / 96.4 / 3.16 s | > 600 / 42.6 / 1.28 s | 1.19 / 0.37 s |
| LSKE (77,496) | > 600 / 65.9 / 8.35 s | > 600 / 34.2 / 4.33 s | 4.51 / 1.74 s |

"Scoped only" is the v0.44.0 SQL against an indexed temp copy of the group, with no
prefilter. Every walk returned the same sorted arrays in every form that finished.

**Open.**

- **Upstream walks** are unprefiltered. `fwa_upstream()` always requires the feature's wscode to
  equal or lie below the segment's (`wscode_b <@ wscode_a`); the blue-line test sits inside
  that, not beside it. So its prefilter would be one arm, descendant-or-equal codes. It has not
  been measured.
- **`aoi = NULL` on a pre-scoped table** gets the unprefiltered walk. A caller that has already
  copied a group into a working table gets the scoped path by passing `aoi`. A prefilter with no
  temp table would help there, but on a province-wide table its subquery over 11 M rows would
  admit everything.

The per-side code columns are parameters. `blue_line_key`, `downstream_route_measure` and
`watershed_group_code` are FWA names that the function already hard-codes.

## Existence walks

`frs_network_features(result = "exists")` answers whether a segment has any feature
downstream (or upstream) without building the arrays. It is the array walk's own join,
reduced to `SELECT DISTINCT` segment ids, on the same scope and prefilter. Its segments are
the array walk's rows, including a segment whose only features have NULL ids, which gets an
empty array there.

**The join form, not a correlated `EXISTS`.** `EXISTS` can stop at the first match per
segment, but it must drive from the segments. Against the prefiltered features, a derived
table, Postgres runs it as a nested-loop semi-join over the materialized feature list. In
CHWK CH that is about 5,200 rows tested per segment, with no index (11.4 s under
`EXPLAIN ANALYZE`, against 2.8 s for the join; 6.1 s against 2.6 s timed). Across SALR, CHWK
and LFRA it is 1.1× (SALR) to 15× (LFRA) slower than the join. Against the feature view
itself, unprefiltered, so each segment could probe the view's own indexes, it did not finish
in 5 minutes in CHWK, where the join takes 2.6 s. The join drives from the admitted features
and probes the temp table's indexes, which is #272's plan.

**What it saves is small, because the join is the cost.** On link's natural barrier views,
SETN's CH walk (180,313 segments with a barrier downstream) takes 41 s through
`result = "exists"` and 50 s through the arrays, end to end, which includes the arrays'
transfer and R parse. Across SALR, CHWK, LFRA and SETN, the exists mode is 1.00× to 1.24×
faster end to end, rising with the number of segments reached. In SETN CH the join makes
the 4,829,028 pairs in 37.9 s of the array walk's 45.3 s (`EXPLAIN ANALYZE`), and the sort
of the pairs spills 538,912 kB to disk, which is link#394's 4.83 M pairs and 526 MiB. The
spill is real, but it is the smaller part. link#394's second lever, walking each distinct
feature set once, removes whole walks rather than part of each.

A digest that reads only a subquery's id column times the walk without its arrays, because
Postgres replaces an unread `array_agg` output with `NULL`. To time the arrays, read them
(`sum(cardinality(feature_ids))`).

## GEOS

GEOS 3.9.0 (local fwapg) returns `LINESTRING EMPTY` for the intersection of an exactly vertical line at x = 1000 with a box that `ST_Contains()` says holds it; x = 1500 and slanted lines are fine.
