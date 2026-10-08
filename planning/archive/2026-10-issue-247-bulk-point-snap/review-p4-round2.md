# Review — #247 Phase 4 parity check, round 2

Scope: `data-raw/point_snap_parity_check.R`, `data-raw/logs/point_snap_parity_247/*`,
`planning/active/findings.md` ("Parity with `link::lnk_points_snap()`").
Context read: `R/frs_point_snap.R`, `link/R/lnk_points_snap.R`.

## Findings

- **[severity: fragile]** data-raw/point_snap_parity_check.R:92-98, 147-168;
  planning/active/findings.md table. The nf1 categories do not partition the
  crossings. `nf1` is a FULL JOIN of two `CROSS JOIN LATERAL` outputs, so a
  crossing that neither function snapped has no row at all. That makes the
  `"neither"` branch (line 93) unreachable, and these crossings appear in no
  summary column: 69 in BULK (1,780 - 1,711) and 1,692 in ALL (19,905 - 18,213,
  confirmed by an anti-join against `working.*_pscis`). The findings table lists
  "PSCIS crossings 1,780 / 19,905" above categories that add up to 1,711 /
  18,213, and nothing on the page accounts for the difference. Nothing in the
  check is wrong because of this, since "both unsnapped" is agreement. But if a
  regression stopped both functions from snapping a block of points (an SRID or
  geometry-type problem in the shared input, say), this bucket would grow with
  no column to report it. Fix: derive the bucket from the points table, e.g.
  `nf1_neither = n_pts - nrow(nf1)`, or LEFT JOIN `tbl_pts` into the nf1 query
  so `"neither"` can actually occur. Add the row to the findings table so the
  categories add up to `n_pscis`. `nf5_crossings` (1,711 / 18,213) has the same
  gap.

## Verified (no defect)

I re-ran the check from a scratch copy (tables renamed, logs written to the
scratchpad, scratch tables dropped afterwards). It reproduced the committed
ALL summary exactly, and I then probed each round-1 fix directly:

- **NA propagation in the nf5 SQL (round-1 fix 2):** none possible. On a
  one-sided crossing `n_fresh` (or `n_link`) is `coalesce(...,0)`, so
  `0 = 5` is FALSE and SQL `FALSE AND NULL` = FALSE. `tie_set` is never NULL.
  `link_999` and `drm_same` are coalesced, and `same_set` is
  `bool_and` over a never-NULL `in_both`. nf1 `status` cannot be NA either:
  the measure is never NULL when the blue_line_key is set. The nf5
  categories partition `nf5_crossings`: 18,108 + 86 + 0 + 19 = 18,213.
- **`tie_set` is not a proxy:** every one of the 105 differing nf5 sets is
  either a link `999.*` crossing (19) or one where the unshared candidates
  match in count and fresh's are all lower `linear_feature_id`s than link's
  (86). There are 0 others, so "differs only at the cut-off tie" holds.
- **nf1 `tie` is not a proxy for a measure discrepancy:** in all 22 ties link and
  fresh picked different `linear_feature_id`s (fresh's always the lower one) on
  the same blue_line_key, with distance difference exactly 0. That matches the
  findings bullet ("two segments meeting at a vertex"). No crossing has the same
  blk + measure on different segments.
- **`nf5_drm_mismatch` excludes the 19 link-999 crossings:** their shared
  candidates also have 0 measure mismatches, so leaving them out hides nothing.
- **link_999 bucket hides nothing:** for the 8 nf1 crossings fresh leaves
  unsnapped, link's nf5 lists no non-`999` candidate within 150 m. For the
  3 that fresh does snap, fresh's pick equals link's nearest non-`999` candidate
  (same segment and measure). In all 19 nf5 link-999 crossings, every non-999
  candidate link lists is in fresh's set.
- `stream_crossing_id` is unique with no NULL geometry, so the joins cannot
  multiply rows. link's distance (to `ST_ClosestPoint`) and fresh's (to the
  line) differ by about 4e-11, well inside the 1e-6 tie tolerance.
- Teardown: `drop_all()` at the start and the end, then `dbDisconnect()`. No
  `parity_247_*` tables remain in fwapg.
- Provenance stamp: HEAD is `db1e959` and the working tree was dirty during the
  logged run, but the only change under `R/` is a roxygen comment in
  `R/frs_candidates_pick.R`, so the stamp does describe the snap code that ran.

## Verdict

One fragile item, an accounting gap in the summary. The agreement figures and
round-1 fixes check out against the live data.
