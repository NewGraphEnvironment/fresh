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
