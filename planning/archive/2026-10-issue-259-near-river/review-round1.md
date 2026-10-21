# Code check, round 1: #259 near_river (branch diff merge-base...HEAD)

## Checklist read

- code-check-infra.md: in full.
- code-check.md: the prose of all 14 H3s under `## Mechanisms` (tables and evidence blocks skipped). Of the 30 other headings, none read in full.
- code-check-r.md: read 8 sections: "Postgres row order is never fixed…", "`sprintf("%g", x)` writes `Inf` and `NA` into SQL…", "An `information_schema` lookup…", "A `data-raw/` script must load the source tree…", "Tests that silently do not run", "R's `yaml` returns a mixed int/float sequence…", "Under `R CMD check`, tests run from a temp dir…", "`on.exit()` at a script's top level never fires". About 103 others not read.
- code-check-spatial.md: read 3 sections: "FWA `upstream_route_measure` misses the next segment's start", "FWA main flow is not edge type 1000 alone", "A Freshwater Atlas main stem's downstream end lies on the receiving river's centreline". About 80 others not read.
- code-check-shell.md: no section read. The diff contains no shell code; the data-raw script's two `system("git …")` calls are read-only.

## Findings

- **[severity: bug]** R/frs_near_river.R:291-296 (the `origins` CTE in `.frs_near_river_walk_sql()`). Segments with no local code do walk, and they get `near_river` rows. Their distances are straight-line jumps across network the walk never visits.
  - **What the code says.** The roxygen at R/frs_near_river.R:44-48 says such a segment "never walks, so it gets no row and never passes on `near_river`". `frs_habitat_predicates()` (R/frs_habitat_predicates.R, the `near_river` section) says the same, and so does NEWS 0.41.0 ("A segment with no local watershed code never walks"). The verbose line prints "N with no local code did not walk".
  - **What happens.** `origins` does not filter on `localcode_ltree IS NOT NULL`. `FWA_Downstream()` (fwapg, 11-argument body) has a branch, `wscode_ltree_b = localcode_ltree_b AND wscode_ltree_a != wscode_ltree_b`, that ignores `localcode_ltree_a`. So a NULL-localcode origin is joined to the bottom row (wscode = localcode) of every ancestor line. A main-flow 1400 with NULL localcode also walks its own line by measure (criterion 1). Everything in between is skipped, so `jump_m` carries a straight line from the side channel to an ancestor's mouth.
  - **The resulting distance can be wrong in both directions.** It can admit a segment whose true network path is longer than `distance_max`, because a straight line is never longer than the path. It can also miss the actual nearest river, for example the main stem the side channel sits on, whose rows are excluded by `wscode_a != wscode_b`. When the jump is no longer than `entry_max` and lands in the target polygon, the bank rule subtracts it as well.
  - **Measured.** Probe on a scratch copy, not the repo. Table: BULK built from raw `fwa_stream_networks_sp`, 32,472 rows, 2,426 with no local code, `mad_m3s` = wet's annual pick. Call: `frs_near_river(q = 3, d = 20000)`.
    - 93 segments with no local code got rows: 1100: 43, 1450: 42, 1350: 6, 1150: 1, 1300: 1. The smallest distance was 1,770 m.
    - The verbose line printed "2426 with no local code did not walk" in the same run.
    - The join: 541 no-code origins of edge types 1100/1150/1300/1350/1450/2300 match main-flow rows only through the bottom-segment branch (5,346 rows). 245 main-flow 1400s with no local code match rows on their own line.
    - None fell within 1 km in BULK, so the BULK check could not show it. The check script also samples only starts that have a local code, at data-raw/near_river_check.R:227. A side channel near a parent's mouth elsewhere would pass at 1 km. 1100 and 1150 are in link#364's example rule.
  - **Fix.** Add `AND localcode_ltree IS NOT NULL` to the `origins` WHERE. That makes the docs, NEWS and the verbose count true as written.

## Invariants checked (hold)

- **Rules without `near_river` compile byte-identically.** `size_parts` is appended last, cw before mad, in the old order, and nothing else is appended after it (R/utils.R).
- **The EXISTS references only `s.id_segment` and `s.watershed_group_code`.**
- **Answers do not depend on the other specs in a call.** Origins are filtered per discharge (`origin_mad < q.discharge_min`). Path order is total (it ends on `id_segment`), and `path_m` is monotone. For a contiguous path, a row the `ST_DWithin` prefilter drops forces every later row past the cap. Its upstream end is more than `cap` from `o.geom`, and `path_m` is at least the straight distance. Measured on BULK raw FWA: (Q=1, D=1000) alone against (1, 1000) + (10, 8000) gives 3,365 = 3,365 rows and 0 differing distances.
- **`dist_m` is never negative.** Both terms of `connector_m` are in `path_m` for every non-connector row: connector `below_m` from earlier rows, and the row's own jump. The subtraction is clamped with `greatest(…, 0)`. The probe found 0 negative distances.
- **Only rows with `mad_m3s` NULL or below a discharge get a row at it** (the JOIN condition on `origin_mad`).
- **Mixed-group tables.** `id_segment` is unique within one working table, because it is seeded from `linear_feature_id` and breaks allocate new ids. So `PARTITION BY o.id_segment` is safe on a single table.
