# Review: Phase 4 parity script, round 1

Scope: `data-raw/point_snap_parity_check.R`, `data-raw/logs/point_snap_parity_247/*`,
the "Parity with `link::lnk_points_snap()`" section of `planning/active/findings.md`.
Context read: `R/frs_point_snap.R` (`.frs_point_snap_sql()`), link's `R/lnk_points_snap.R`.

## Findings

- **[severity: bug]** data-raw/point_snap_parity_check.R:38,46 — `on.exit()` at a
  script's top level never fires under `Rscript`, because the global frame never
  exits. Verified: after `Rscript data-raw/point_snap_parity_check.R BULK 150`, all
  five tables (`working.parity_247_pscis`, `_link_nf1`, `_link_nf5`, `_fresh_nf1`,
  `_fresh_nf5`) were still in `working`. Every run leaves them behind, and the
  `dbDisconnect` registered on line 38 never runs either. The `drop_all()` at
  line 45 hides this on reruns. Fix: call `drop_all()` and `DBI::dbDisconnect(conn)`
  explicitly at the end of the script, or use
  `withr::defer(..., envir = globalenv())`. I dropped the leftover tables after
  my run.

- **[severity: fragile]** data-raw/point_snap_parity_check.R:112-127 — the nf5
  `tie_set` test is valid only when both sides were truncated at
  `num_features`, and the script never checks that. A candidate listed by only
  one side is a cut-off tie only if both sides returned 5 rows. Without the
  count check it can pass vacuously:
  - When fresh snaps a crossing that link does not, and fresh has one candidate
    (or all its candidates are equidistant), every row is fresh-only at
    `d_max`. `tie_set` is then TRUE, and the crossing counts as a tie, not as
    `nf5_differ_set`.
  - When fresh returns fewer than 5 (its set ran out within `tolerance`), an
    extra link or fresh candidate at fresh's `d_max` is a real difference. The
    LIMIT never cut either set, yet it is still classified as a tie.

  It also fails the other way: when a crossing has link rows but no fresh rows,
  `d_max` is NULL, `bool_and` returns NULL, and `nf5_tie_set` / `nf5_differ_set`
  become `NA` instead of counting a difference. That failure is loud, not
  silent.

  Today's figures are not affected. I re-ran both snappers on all 19,905 PSCIS
  crossings: all 86 `tie_set` crossings have exactly 5 link and 5 fresh
  candidates, and `nf1_fresh_only = 0` independently rules out the
  single-candidate case. The "nf5 other differences = 0" row depends on this
  cross-check, not on the nf5 logic alone. Fix: also require
  `count(l) = count(f) = num_features` for `tie_set`, and count the rows where
  `d_max` is NULL as differ.

- **[severity: fragile]** data-raw/point_snap_parity_check.R:128,150 —
  `nf5_same_drm` is computed only over `same_set` crossings. Measures on the
  candidates shared by the 86 `tie_set` crossings are never checked, so a
  measure mismatch there would not appear in any column. findings.md still
  reads "nf5 other differences = 0". I checked directly: 0 shared-candidate
  measure mismatches in those 86 crossings, so the claim holds today, but the
  script does not prove it. Fix: check `same_drm` for `tie_set` crossings too.

## Checked and OK

- **nf1 `tie` (distance equality only).** It does not over-include anything in
  these data. All 22 ALL ties (and the 1 in BULK) have the same `blue_line_key`
  and measures exactly 1 m apart. Both snappers use the identical
  `CEIL(GREATEST(drm, FLOOR(LEAST(urm, ...))))` formula, so a shared vertex
  gives `ceil(drm_up)` on the upstream segment and `floor` on the downstream
  one. In every sampled tie, fresh picked the lower `linear_feature_id`, as
  designed.
- **nf1 `differ`.** It is a true residual: it catches every non-999 crossing
  that both sides snapped with a different blk or measure at unequal distance.
  `link_only` and `fresh_only` catch one-sided snaps, so none slip through.
  Ordering puts `link_999` before `link_only`, so a link 999 pick that fresh
  leaves unsnapped is not double-counted. An NA comparison yields an NA status,
  so the sums go NA (loud), not 0.
- **Duplicates.** None in `stream_crossing_id` in the PSCIS source, link nf1 or
  fresh nf1, so the FULL JOINs do not multiply rows.
- **The three `999.*` crossings fresh snapped (807, 1467, 63483).** In each,
  fresh's pick is exactly link's nearest non-999 nf5 candidate: same
  `linear_feature_id`, measure and distance. That confirms the guard difference
  is the only cause. The 8 / 3 split in findings.md matches `ALL_nf1.csv`.
- **`fresh_wsg_na`.** It measures what findings.md claims, that the nf1 fresh
  output carries a non-null `watershed_group_code`. It is nf1 only, and it does
  not check that the WSG is correct, but findings.md claims no more than that.
- **Rerun stability.** Re-running BULK reproduced `BULK_summary.csv` and
  `BULK_nf1.csv` byte-for-byte. Only the timestamp in `BULK.txt` changed.
- **Unchecked figure.** The runtime row in findings.md is not recorded in any
  log, since the times are only `message()`d. It is unverifiable, but harmless.
