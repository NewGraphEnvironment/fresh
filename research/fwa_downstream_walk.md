# Walking FWA downstream: what `FWA_Downstream()` and the working table give a walk

**Verified:** 2026-10-21 on local fwapg (`whse_basemapping`), BULK working table from `frs_network_segment()` · **Issues:** #259 · **Produced by:** `data-raw/near_river_check.R` (logs `data-raw/logs/near_river_259/`), probes in `planning/archive/2026-10-issue-259-near-river/` (findings and review rounds 1 to 6).

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

## GEOS

GEOS 3.9.0 (local fwapg) returns `LINESTRING EMPTY` for the intersection of an exactly vertical line at x = 1000 with a box that `ST_Contains()` says holds it; x = 1500 and slanted lines are fine.
