# Review: fresh#240 phase 3, round 2 (bucket connectivity + trace generalisation)

Reviewed the staged diff, all of `R/frs_habitat.R` around `.frs_run_connectivity()`,
`.frs_bucket_connected()` and `.frs_trace_downstream()`, and
`tests/testthat/test-frs_bucket_connected.R`. Every probe ran in a copy of the repo
(scratchpad `fresh_copy_r2`); the repo's working tree was not touched.

## Findings

- **[severity: fragile]** R/frs_habitat.R:1423-1424 (trace 2 origin) and
  R/frs_habitat.R:1449-1450 (trace 3 origin). **Neither origin choice is pinned by
  any test, and a wrong choice gives wrong distances while the suite stays green.**
  Each origin is the row picked first by `DISTINCT ON ... ORDER BY`:
  - trace 2: the polygon outlet, which is `downstream_route_measure` ascending;
  - trace 3: the bottom of the spawning cluster, which is `wscode_ltree` ascending
    (parent before tributary), then localcode and measure ascending.

  Every fixture is built so that reversing these orders does not change the outcome:
  - Each lake is two 1000 m lines, and the "within" tests use D = 3000. So tracing
    from the top of the lake instead of the outlet adds 1000 m and still passes.
  - Every spawning cluster is a single segment, so "lowest point" is never actually
    chosen.
  - No cluster spans two wscodes.

  Mutation, run in the copy:
  - Change trace 2's order to `b.localcode_ltree DESC, b.downstream_route_measure DESC`:
    **FAIL 0 | PASS 22**.
  - Change trace 3's order to `c.downstream_route_measure DESC`: **FAIL 0 | PASS 22**.

  Both mutations change the shipped result. Probe at D = 1500, unmutated vs mutated:
  - lake above spawning (outlet 1000 m above spawning): `TRUE TRUE` vs `FALSE FALSE`;
  - lake below a two-segment spawning cluster (cluster bottom 1000 m above the lake):
    `TRUE TRUE` vs `FALSE FALSE`.

  Any D between the true distance and the true distance plus one segment
  discriminates. Probe script: scratchpad `probe_origin.R`.

  This is exactly the "origin selection still unpinned" case asked about. Today's code
  picks correctly; only the pinning is missing.

## Checked and sound (no finding)

- **The round-1 fix works and can fail for the right reason.**
  - At `scale = 0.01` the largest fixture extent is 50 m, so `ST_DWithin(…, 500)` passes
    every segment, and D = 500 vs 3000 can only be decided by the `dist_to_origin < D`
    cap.
  - The D = 3000 → TRUE half rules out a trace that returns nothing.
  - Both fixtures use single-segment spawning, so scaling cannot change DBSCAN
    clustering (contiguous segments still touch at any scale). No other path depends
    on the scaled geometry.
  - `identical(fx, .bkt_lake_above_spawning)` compares the same closure object, so the
    lake ids are selected correctly.
- **The prefilter is exact, not merely approximate.** Let R be the first segment in
  window order whose cumulative distance reaches D.
  - Every segment before R has a cumulative length `c_j` < D. Its geometry is within
    straight-line distance `c_j` of the origin geometry, because cumulative length is
    at least the path length, which is at least the straight-line distance. This holds
    even for a parent segment straddling a confluence, which passes through the
    confluence point.
  - So every segment before R is retained by the prefilter, and every later segment
    keeps a cumulative sum ≥ D whether or not R or later segments are pruned.
  - Pruning can only remove segments the cap would remove anyway. The only exception
    is sub-metre `length_metre` vs `ST_Length` rounding at the boundary.
- **The window `PARTITION BY` / `ORDER BY` is pinned for both paths.** The
  `downstream` / `downstream_capped` template text is shared between the gradient and
  no-gradient branches, and the golden SK fixture covers it byte for byte. `rn` is read
  only in the gradient branch.
- **Origin ids are unique per origin.**
  - Trace 2 maps `origin_id = id_segment`, one row per (waterbody_key, blue_line_key).
    `id_segment` is unique within one working `table` (`.frs_add_id_segment`).
  - Trace 3 maps `origin_id = cluster_id`, and DBSCAN with minpoints 1 never yields a
    NULL id.
- **Every habitat join and the UPDATE match `watershed_group_code`**, and the
  shared-table test covers it.
- **Default-call SQL is unchanged** (golden test passes). The suite on the unmutated
  copy: FAIL 0 | PASS 22.
