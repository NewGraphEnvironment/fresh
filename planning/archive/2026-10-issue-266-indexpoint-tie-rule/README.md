## Outcome

`frs_point_snap()` now breaks an exact distance tie on **position** — the segment with the
higher raw `downstream_route_measure`, the one starting at the shared vertex, then
`linear_feature_id` — matching the rule fwapg adopts in NewGraphEnvironment/fwapg#41, so fresh
and `fwa_indexpoint()` agree on which segment a tie belongs to and therefore on its local code.
Three ordering sites carry it, not the two the issue named; the load-bearing one is the lateral's
own `ORDER BY ... LIMIT`, the only one that matters at `num_features = 1`. The key is the **raw**
measure, carried out of the lateral as `measure_raw`, because two segments sharing a vertex on a
whole metre clamp to the same emitted value and would fall back to the old rule.

The issue's other two parts came with a new exported helper, `frs_migration_trial()`, which applies
pending migration files in one transaction and rolls them back when the calling frame returns, and
with `data-raw/point_snap_tie_sweep.R`, which runs fresh's own inputs through three states — base,
the tiebreak migration alone, both migrations — to attribute each change rather than infer it.
**No database was migrated**; that waits on fwapg#41 / smnorris/fwapg#201.

What was learned, beyond the code: the issue's three gauge points mostly do not pin anything once
re-measured through fresh's per-segment snap rather than `fwa_indexpoint()`'s per-stream one, and
the obvious stronger pin — a point on the shared vertex — is a three-way tie where `ST_Distance`
is not bit-equal, so the pre-change code already returned the new answer by accident. The head
case the migration fixes is **unreachable** from fresh's own clamped measures, and the reason a
head measure could never be placed is not the half-open range but that the old `fwa_locatealong()`
compares bounds rounded to 4 decimals. Four code-check rounds found 15 defects, two of them
fail-open holes in the SQL screen (a missing `"..."` token class, and an ASCII-only identifier
class against PostgreSQL's `[A-Za-z\200-\377_]`), and round 3 closed that class with a measured
enumeration of PostgreSQL's lexical constructs rather than another hunt.

Research: [research/fwa_point_snap.md](../../../research/fwa_point_snap.md) carries the rule, the
sweep numbers and what the migration does not fix.

## Measurement

- **The tie pin.** 08KD006 on the Willow River: 703862843 and 703862887 tie to the bit at
  `67.563693805068` m, clamped measures 14040 and 14041, local codes `100.594120.061391` and
  `100.594120.063640` (a tributary joins at the vertex). Six tests red on `main`, green after.
- **The KNN scan survives the new key**: `Index Scan ... Order By: (geom <-> ...)` under an
  `Incremental Sort` with the distance as `Presorted Key`.
- **The sweep**, over 49,725 snapped positions (all 19,905 PSCIS assessments + 5,000 fish
  observation points, tolerance 150, `num_features = 5`), 23,540 CSV measures and 970 expensive
  positions: **0** of fresh's own positions fail to resolve in any state; **4** CSV measures that
  missed now resolve; **1** position stops raising `line_interpolate_point: 2nd arg isn't within
  [0,1]`. Every change belongs to `202610240132__indexpoint_tiebreak`; `drop_exbc` moves nothing.
- **A pre-existing fwapg defect the migration does not fix**: 293 of 970 positions (30%) error
  identically in all three states with `more than one row returned by a subquery used as an
  expression`. Worth an upstream report.
- **Ties are mostly not the positional kind**: 3,463 tied groups, only 440 within one stream.
- **`whole_metre_top = 0`** — no candidate segment has an integer `upstream_route_measure`, which
  is why the head-case pin had to be constructed by query. Of 400 blue lines sampled, their own
  top measure resolves on **2** before the migration and **218** after.
- **Batched `fwa_locatealong` is 0.3 ms a call** against 70 ms for a single round trip, which is
  what made the exhaustive position run affordable; `fwa_watershedatmeasure` is 0.64 s a call,
  which is why the expensive calls are sampled.
- **A precision limit in fresh, measured and deliberately not fixed**: `frs_point_locate()`
  interpolates the measure with `sprintf("%s", m)`, 15 significant digits, which for 185 of those
  400 streams rounds the top measure *up* and outside even the reworked closed range. `%.17g`
  would round-trip.
- **Reproducibility**: three independent full sweeps produced byte-identical report bodies
  (md5 `a455f23be9bf879b00bbf373c381b9ba`). Full suite at the end: 47 files, 687 tests, 1,968
  passing, 0 failures, 6 skips.

## Evidence

`data-raw/logs/indexpoint_266/`

## Owed

- link#383: hand it the measured rule, the sweep numbers and `fresh::frs_migration_trial()`.
- Migrating any database waits on NewGraphEnvironment/fwapg#41 / smnorris/fwapg#201 — not this
  issue, and not this branch.
- Whether wet's internal copy collapses onto `fresh::frs_migration_trial()` is wet's call; note
  it on wet#132 rather than changing wet here.

Closed by: commit b36a133 / PR pending
