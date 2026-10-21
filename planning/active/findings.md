# Findings — Rule condition: a river of at least Q m³/s within D m downstream (#259)

## Issue context

**If done:** a habitat rule can admit a segment that fails its size test when a large river lies a short distance downstream, so small streams and wetland reaches beside a river count, and those far from one do not. **If never:** a rule can only test a segment's own size and slope, and a config that wants "beside a river" has to fall back on a free pass (`thresholds: false`) or a long connection distance.

## Problem

Juvenile chinook use small streams close to large rivers. Tuning chinook rearing against provincial electrofishing records found the best rules all admit a small stream when a river of about 3 m³/s lies within about 1 km downstream. fresh's rule grammar has no way to say that: a rule tests a segment's channel width, discharge and gradient, and `requires_connected` measures distance to spawning, not to a river.

## Proposed

A rule condition, for example:

```yaml
- edge_types_explicit: [1000, 1100, 2000, 2300, 1050, 1150]
  near_river:
    discharge_min: 3       # m³/s, read from the configured discharge source
    distance_max: 1000     # m along the network, downstream
```

A segment passes the rule when its gradient is in range and **either** its size test passes **or** a segment with discharge of at least `discharge_min` lies within `distance_max` downstream. Names are a starting point.

Points to settle:

- **Measure to the river's bank, not its centreline.** Where a tributary meets a double-line river, its line crosses the river polygon as a connector (FWA edge type 1450) to the centreline. Those connectors carry the tributary's own small flow, so the walk must not stop on them, and the distance should end where the line enters the river polygon.
- **The discharge source is the bundle's** (fwapg or wet); a segment with no discharge value fails the size test but can still pass on distance.
- **Measured from the segment's downstream end**, so a long segment whose lower end is within the distance passes whole; worth saying in the docs.
- A working SQL walk that does this for visit sites and segments exists, and can be contributed as the starting point.

Consumer: link, which would carry the two numbers per species and use the condition for stream and through-wetland lines (NewGraphEnvironment/link#364).



## Probe: windowed near-river trace on BULK (2026-10-20, local fwapg, wet pick flows)

BULK working-table stand-in (30,046 FWA rows with a localcode, no 6010 / 999), `mad_m3s` = wet pick (`scenario = historical, month = 0, pick`, 0 read as NULL): 30,011 with flow, 1,087 at >= 3 m³/s.

Trace: origins = every row; `FWA_Downstream` join; `blue_line_key = watershed_key`; `ST_DWithin(t.geom, o.geom, 1000)`; path window `-t.length_metre + SUM(t.length_metre) OVER (PARTITION BY origin ORDER BY wscode DESC, drm DESC)`; connector window `SUM(length_metre) FILTER (WHERE edge_type IN (1400, 1450)) OVER (PARTITION BY origin, waterbody_key ORDER BY …)`; targets `mad_m3s >= 3 AND edge_type NOT IN (1400, 1450)`, nearest per origin with `path - connector <= 1000`.

| measure | value |
|---|---|
| trace wall clock | 5.2 s |
| origins with a 3 m³/s river within 1 km (bank) | 3,249 |
| of which admitted only by the bank subtraction | 8 |
| of which the subtraction moved | 1,003 (mean 9.9 m) |
| targets by edge type | 1250: 2,822; 1000: 416; 1200: 11 |
| paths where a same-polygon connector sorts after its target | 0 of 3,299 |

Province-wide: 1450 rows inside river polygons 208,409 (mean 45 m, p90 92 m; 68,860 with NULL localcode, 95,495 with `blue_line_key <> watershed_key`). fwapg discharge covers 69,343 of 190,678 edge-1250 rows; BULK 0 of 1,118 (wet pick: 1,114).

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Phase 4: BULK against an independent walk (2026-10-21 UTC, fresh 2362aa0)

`data-raw/near_river_check.R BULK 3 <reference SQL>`; log `data-raw/logs/near_river_259/bulk_*`. Working table from `frs_network_segment()` (no breaks), wet's annual pick as `mad_m3s`. The reference walks route measures on raw FWA to the centreline of the first primary-flow segment at or above 3 m³/s.

| measure | value |
|---|---|
| segments / at or above 3 m³/s / no local code | 32,472 / 1,087 / 2,426 |
| walk time, 1 km / 20 km | 14.7 s / 62.7 s |
| within 1 km / within 20 km | 2,118 / 22,523 (22,617 before code-check round 1 kept no-local-code rows out of the origins; 2,116 within 1 km before round 2 made the bank rule subtract only the in-polygon part of a jump) |
| negative distances | 0 |
| 1 km and 20 km walks disagreeing within 1 km | 0 |
| bank offset (centreline minus bank), found by both | 16,051 of 22,501; mean 38.2 m, max 599.1 m |
| bank distances shorter than the straight line to the target's polygon (independent bound) | 0 of 1,122 |
| rows for segments at or above 3 m³/s | 0 |
| Coffin Creek (link#364's example) through wetlands | 4,594 to 12,337 m: fails at 1 km |

2,455 starts, every residual attributed: agree 644 (max 0.003 m), bank 1,122 (subtraction alone, mean 33.6 m), beyond 438 (past 20 km both), entry 231 (the two walks enter a parent line at different points: fresh counts the jump, less any part inside the target's polygon; the reference counts nothing; median 201 m), nested_code 20 (2 targets; one BULK main-flow row carries a local code nested under a tributary's, 2,013 such rows province-wide), unexplained 0. Round 2's example (segment 17078330, a tributary ending on a side channel 331 m from the Bulkley's polygon) read 700.6 m and now reads 1,041.4 m.

**What the check found and fixed (commit 7320a21).** The first run had 183 negative distances (floating-point residue, −2e−13 m: clamped) and 127 segments within 1 km that the 20 km walk found and the 1 km walk did not. Cause: a path that leaves the table and re-enters (a tributary joining its river in a stretch outside BULK) counted the stretch as nothing, a 17.8 km stretch read as 973 m, and only the straight-line prefilter of the smaller reach hid it. Fix: count every jump between path rows at its straight length. That surfaced two more: a tributary meeting its parent part-way along a row counted the whole row (fix: walk only below the entry point, `ST_LineLocatePoint()`), and on one line a row upstream of the origin carried a lower local code, so `FWA_Downstream()`'s code branch put it on the path (fix: on the origin's own line the measure decides).

**Plan assumptions that did not hold.**
- "A connector with NULL localcode is never on the working table": `frs_network_segment()` keeps side-line rows with no local code (BULK 2,426: side channels 1100 238 of 358, 1350 177, 1450 486, plus 1,513 placeholder 1400s). Main-flow rows with no local code are dropped. A row with no local code never walks; province-wide 50,280 of 83,642 side channels (1100) have none. Only 5 of BULK's 238 such side channels start on a 3 m³/s river.
- About a third of connectors (BULK 574 of 1,624 edge 1450) are side lines, which the main-flow walk drops; the walk jumps from the tributary's mouth to the centreline, and that jump is the bank (subtracted when no longer than the longest side-line connector run).
- `Lmax` per `waterbody_key` alone would sum every tributary's connector in a polygon; it is per `(waterbody_key, blue_line_key)`.

**Follow-up worth filing (draft, not filed):** side channels with no local code cannot walk, and the issue's example rule lists 1100 and 1150. A walk could start them from the point where they rejoin a main-flow row (`ST_StartPoint`, nearest main-flow row), as the reference does at every hop.
