# Code check, round 2: #259 near_river (branch diff merge-base...HEAD, 63559ba)

## Checklist read

- code-check-infra.md: in full (table rows skipped).
- code-check.md: the prose of all 14 H3s under `## Mechanisms` (tables and evidence blocks skipped). None of the other headings read.
- code-check-r.md: 5 sections read: "Postgres row order is never fixed…", "`sprintf("%g", x)` writes `Inf` and `NA` into SQL…", "An `information_schema` lookup…", "A `data-raw/` script must load the source tree…", "`on.exit()` at a script's top level never fires". About 106 not read.
- code-check-spatial.md: 3 sections read: "FWA `upstream_route_measure` misses the next segment's start", "FWA main flow is not edge type 1000 alone", "A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline". About 80 not read.
- code-check-shell.md: none read (the diff has no shell code).

## Round 1 fix

Correct. With `localcode_ltree IS NOT NULL` on origins, `FWA_Downstream()`'s branch 1 (`subltree(localcode_a, …) > localcode_b`) applies again, so the rows between a confluence and an ancestor's bottom row are on the path. The bottom-row branch (`wscode_b = localcode_b AND wscode_a != wscode_b`) still fires for an origin with a local code, but every row it admits is genuinely downstream (an ancestor line's bottom segment lies below all its tributaries), so it skips nothing. The third branch (same wscode, different blue line, `localcode_a > localcode_b`) only admits main-stem rows below a side-channel origin's code. The new test sets row 1's localcode to its wscode, so it exercises the branch the fix is about.

## Findings

- **[severity: bug]** R/frs_near_river.R:279-285 (`conn_sql`, the `jump_m <= entry_max` term) — the bank rule subtracts jumps that are not bank crossings, so `dist_m` can be shorter than the true distance to the bank and segments beyond `distance_max` pass.
  - **What the code promises.** The roxygen (R/frs_near_river.R:30-32) says "Any other jump between consecutive rows of the path is counted at its straight length: a side channel the walk does not follow, or a stretch of river outside `table` that the path leaves and re-enters". `.frs_near_river_walk_sql()`'s doc says a jump into the polygon is subtracted only as a side-line connector crossing.
  - **What it does.** Every jump that lands on a row of polygon P and is no longer than `entry_max` (the table's longest side-line connector run, 412 m on BULK) is subtracted, whatever the jump crosses. A tributary that joins a **side channel** of the river, which then enters the river's polygon further on, produces exactly such a jump: the walk drops the side channel and jumps from the tributary's mouth, on dry land, to the centreline. The whole jump is subtracted, including the stretch outside P. A short re-entry jump (a path leaving the table and coming back into P within `entry_max`) is subtracted the same way.
  - **Measured.** Scratch copy of the branch, BULK from raw `fwa_stream_networks_sp` (32,472 rows), with `mad_m3s` set to wet's annual pick as in the check script. Run: `frs_near_river(q = 3, d = 5000)`, `entry_max` 411.7 m.
    - Subtracted jumps: 1,616. Of these, 984 start more than 10 m outside the landing polygon (`ST_Distance(prev_pt, polygon)` against the rivers, lakes, manmade and wetlands polygons with that `waterbody_key`), and 189 start 200 to 400 m outside it.
    - 9 origins are within 1 km only because of it. Their reported `dist_m` plus the part of the jump that lies outside the polygon (a lower bound on the true bank distance) exceeds 1,000 m.
    - Example: origin 17078330 (wscode 400.431358.802619.505205). The path is 17078986 (583 m), then 17079221 (118 m, edge 1000, no waterbody, the bottom of 400.431358.802619), then a 362.6 m jump to the Bulkley row 17079967 (edge 1250, polygon 329706605, 4.5 m3/s). The jump starts 331 m outside polygon 329706605: 400.431358.802619 ends on a side channel (side lines 17079753 / 17080246, edge 1100, wscode 400.431358). Reported `dist_m` 700.6 m. The true bank distance is at least 1,032 m, so the segment passes a 1,000 m rule it should fail.
    - Origin 17082819: the tributary ends in a different polygon (329065263, whose rows are the side channel's 1300 lines), then jumps 369.3 m to polygon 329706585, starting 350 m outside it. The whole jump is subtracted.
  - **Why the BULK check did not show it.** `data-raw/near_river_check.R` classes a residual as `bank` whenever fresh's own centreline walk agrees with the reference within 1 m: "the bank rule's subtraction is the whole difference". So any subtraction, right or wrong, is absorbed into `bank`. The check verifies the subtraction against the same walk that produced it.
  - **Fix direction.** Subtract a jump only when it is a side-line connector crossing. For example, require a side-line connector row (edge 1400/1450, `blue_line_key <> watershed_key`, same `waterbody_key` as the landing row) whose upstream end lies within a small tolerance of `prev_pt`, and subtract at most that connector run's length. Otherwise count the jump, as the docs say.

## Checked and holding

- **Rules without `near_river` compile byte-identically.** `size_parts` is appended last, cw before mad, and nothing else is appended after the mad block (R/utils.R).
- **The EXISTS reads only `s.id_segment` and `s.watershed_group_code`.**
- **No other specs in the call change one spec's answer**, for the walk as written. Origins filter on `origin_mad < q`. Path order is total, because it ends on `id_segment`, which is unique within one table. Window sums use only preceding rows. A row that `ST_DWithin` drops puts every later row on a contiguous path past the cap. The cap allowance holds in practice: the largest `connector_m` on any capped row was 2,983 m against `conn_max` 3,395 m (BULK), and 1,874 m against 2,091 m (LNIC).
- **`dist_m` is never negative.** Every subtracted term is in `path_m` for a non-connector row: earlier connector `below_m`, and jumps up to and including the row's own. (The finding above is about subtraction that is *in* `path_m` but is not bank length.)
- **Only rows with `mad_m3s` NULL or below a discharge, and with a local code, get a row at it.**
- **`subltree()` with an end past the label count** truncates rather than errors (`subltree('100.200', 0, 3)` = `100.200`), so `FWA_Downstream()` cannot abort on shallow local codes.
- **The parser** validates `near_river` before normalising it (R/frs_params.R:164 then :170), so unknown or missing keys are refused.
