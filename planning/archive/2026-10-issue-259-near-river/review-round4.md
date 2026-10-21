# Code check, round 4: #259 near_river (branch diff merge-base...HEAD, c4e4a5e)

## Checklist read

- code-check-infra.md: in full.
- code-check.md: the prose of all 14 H3s under `## Mechanisms` (I skipped the table rows), plus "Bare `y`, `n`, `on`, `off`…" (YAML). I did not read the other non-mechanism headings, about 30.
- code-check-r.md: I read 8 sections: "Postgres row order is never fixed…", "`sprintf("%g", x)` writes `Inf` and `NA`…", "An `information_schema` lookup…", "R's `yaml` returns a mixed int/float sequence…", "`nzchar(NA)` is TRUE…", "`$` on a list partial-matches…", "A database driver's value is not a base R type…", and, from round 3's list, "`on.exit()` at a script's top level never fires". I did not read the other 105 or so.
- code-check-spatial.md: I read 4 sections: "FWA `upstream_route_measure` misses…", "FWA main flow is not edge type 1000 alone", "A Freshwater Atlas main stem's downstream end…" and "`pdist::pdist()`…". I did not read the other 80 or so.
- code-check-shell.md: I read none, because the diff has no shell code.

## How I tested

- **BULK scratch table.** "BULK" below means a scratch copy I built for this review, `zz_review4_nr.streams`:
  - It is `working_bulk.streams` (87,641 segments, link's break segmentation, every row with a local code), with `mad_m3s` set to wet's annual pick, as the check script sets it.
  - In it, 1,411 segments carry 3 m3/s or more, and `conn_max` = 2,983.1 + 77.5 = 3,060.6 m.
  - I dropped the schema afterwards.
- **Synthetic probes.** These ran in `pg_temp` from an rsync'd copy of the repo. I did not edit the repo.
- **Round 3's fix.** In the copy, the near_river tests pass (39 + 63 + 52, with 0 failed and 0 errors). With `least()` replaced by a no-op, "two entries into one polygon…" fails 2 expectations, so the new test does guard the fix.

## (a) Round 3's fix

`least(conn_max, SUM(...))` makes `connector_m <= conn_max` hold by construction. A target with bank distance `<= d` therefore has `path_m <= d + conn_max <= cap`. Every row before it on the path has a smaller `path_m`, and each row lies within that distance of `o.geom`, so `capped` and `ST_DWithin` keep the whole prefix. `conn_max` depends on the table only, not on the call.

The doc additions (code-placed confluences either way, and the check script's `entry` class "either sign") match round 3's finding 2. The check script's new `straight_to_polygon_m` lower bound is sound: the bank cannot be nearer than the straight line to the polygon.

Round 3's finding 1 is closed as stated. Finding 1 below is a different route to the same invariant.

## Enumeration (11 places, current code)

1. **Path order across more than two lines: holds.**
   - Code: `wscode DESC` orders ancestor lines by depth, and the code is unchanged.
   - Probe: on BULK, 0 wscodes are shared by two main-flow lines with a local code.
2. **`LAG(prev_pt)` across a jump, and `below_m` from a far point: holds as documented.**
   - The docs now say "either way", which covers round 3's −14 to −67 m cases.
   - Independent probe: no found distance is shorter than the straight line from the segment's downstream end to the nearest ≥ 3 m3/s main-flow row or its polygon. That is 0 of 4,973 at q = 3, d = 1,000, with a minimum slack of 0.
3. **Rows `FWA_Downstream()` drops: holds (conservative).**
   - Code: unchanged.
   - A jump over the dropped rows counts at its straight length, and only its in-polygon part is subtracted, now capped.
4. **The prefilter (`ST_DWithin` at `cap`) removing rows before the windows: does NOT hold in general (finding 1).**
   - Round 3's argument ("a row beyond `cap` is passed only at `path_m > cap`, so every later row is past `cap`") is true in the run that keeps the row.
   - In the run that drops it, the later rows' `LAG` skips it, so their `path_m` comes from a straight shortcut.
   - The argument holds only when the row before the dropped one ends beyond `cap`, that is, when the dropped row is entered contiguously.
   - BULK: q = 3, d = 1,000 alone, against `c(3, 1, 8)` with `c(1000, 20000, 15000)`. The two runs differ on 0 segments either way, and 0 distances are negative.
5. **Connector rows inside their polygon: holds.**
   - BULK: 88 side-line 1450s, 92 main-flow 1400s and 1,065 main-flow 1450s.
   - All of them have a polygon with their `waterbody_key`, and 0 m of them lies outside it.
6. **A `waterbody_key` that recurs in separate runs along a path: holds.**
   - Round 3 measured 0 answers moved.
   - The only change since is `least()`, which can only lower the subtraction.
7. **Several jumps into one polygon, and the `cap` allowance: holds now.** `least(conn_max, …)` enforces the bound (see (a)), and the mutation test above guards it.
8. **The correlated polygon subquery's column binding: holds.** The code is unchanged: `downstream.prev_pt` and `downstream.geom` bind to the outer row.
9. **The `capped` filter on `path_m` before the subtraction: holds** by (a).
10. **`dist_m >= 0`: holds.**
    - `greatest(..., 0)` clamps it.
    - Probe: 0 negative distances on BULK in the multi-spec run.
11. **Invariants outside the walk: hold.**
    - Every shipped rules YAML compiles byte-identically to merge-base `ed355e1`. I checked fresh's bundled YAML and link's four `configs/*/rules.yaml`, every species, under both `cw` and `mad`: 440 predicate strings, `cmp` identical, 146 of them carrying size parts.
    - The EXISTS reads only `s.id_segment` and `s.watershed_group_code`.
    - Origins require `localcode_ltree IS NOT NULL`, and each spec requires `origin_mad IS NULL OR < q`.
    - `discharge_min` goes through `.frs_sql_num()` both where it is stored and in the predicate.

## Findings

**The mechanism behind both findings.** The walk treats the rows it has *filtered* as if they were the path. `LAG(prev_pt)`, the running `SUM` and the reach are all computed over the rows left after `ST_DWithin` (and, for the reach, after `capped`). The design deliberately reads a missing row as "a stretch the table does not hold: count a straight jump". A row the prefilter or the cap removed is still in the table, though, and whether it is removed depends on `max(distance_max)`, which is the call. Two consumers read that artifact:

- the distance (finding 1);
- the verbose "ended" count (finding 2).

### Finding 1

- **[severity: fragile]** R/frs_near_river.R:333-334 and :344, with :364-366.
- **What happens.** The prefilter can drop a row on the path that is reached by a jump while keeping a later row. The `LAG` then jumps straight from the last kept row to that later row, so its distance is shorter than the walk's own model gives. It also depends on the other specs in the call, which breaks the invariant "one (discharge_min, distance_max) answer does not depend on other specs".
- **Reproduced** (synthetic, `pg_temp`, `conn_max` = 0). Origin O runs (0,0) to (-100,0). The path is A, from (900,0) to (0,0); then a 150 m jump to R, from (1050,100) to (1050,0), 0.2 m3/s, all of it more than 1,000 m from O; then T, from (0,100) to (1050,100), 5 m3/s.
  - `frs_near_river(q = 3, d = 1000)` writes O at **1,000 m**: R is dropped, and the walk jumps (900,0) → (900,100).
  - `q = c(3, 1), d = c(1000, 9000)` writes **no row for O at q = 3**. The walk's own distance is 1,150 m: 900 + 150 + 100 + 0.
- **When it can happen.** It needs a path that leaves the cap through a jump (a side-line connector, an out-of-step row, a stretch off the table, or a code-placed confluence) and comes back within reach. On a contiguous entry the argument in item 4 holds, which is why BULK shows 0 differences.
- **Possible fix.** Cut each origin's path at the first row the prefilter would drop. Every later row is beyond `cap` in truth anyway, because `path_R >= dist(origin, R) > cap`. For example, compute the far test as a column and keep rows only while `bool_or(far)` over the frame preceding them is false, rather than filtering in `WHERE`. Or state the bound in the docs.

### Finding 2

- **[severity: bug, diagnostic only]** R/frs_near_river.R:177-189, with the `discharge_min IS NULL` reach row at :376-379.
- **What happens.** The verbose "walks ended within reach (group outlet or the sea)" counts a walk that was only cut by the cap. A walk is cut wherever the first row past the cap is reached by a jump (`path_m` of the last kept row + `below_m` < cap < the next row's `path_m`), or the prefilter dropped the next row. Its reach `max(path_m + below_m)` is then below `distance_max + conn_max`, and it is counted as ended.
- **Measured on BULK at q = 3, d = 1,000.**
  - Run alone, it reports **332** ended.
  - Run with `c(3, 1, 8)` / `c(1000, 20000, 15000)`, it reports **23** for the same spec, the same table and the same threshold.
  - So about 309 of the 332 continue downstream within the table. The line the docs offer for sizing the outlet-truncation limit overstates it about 14x, and the count depends on the other specs. No data is written from it.
- **Possible fix.** Count as ended only an origin whose last kept row has no row after it in the unfiltered path. A cheap test: `FWA_Downstream()` from the last row's start returns nothing in `table`. Or drop the claim from the message.

/Users/airvine/Projects/repo/fresh/planning/active/review-round4.md
