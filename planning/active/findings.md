# Findings — point_snap_tie_sweep.R sends measures at 7 significant digits (#289)

## Issue context

## Problem

`data-raw/point_snap_tie_sweep.R` builds its `VALUES` list with `format(d$m, scientific = FALSE)` (lines 334-336). `format()` defaults to 7 significant digits and uses one number of decimals for the whole vector, so the sweep does not send the measures it reads:

```r
format(c(1528.8506958829107, 4494.61997946051), scientific = FALSE)
#> "1528.851" "4494.620"
```

The counts in `research/fwa_point_snap.md` from that sweep therefore describe measures rounded this way. That covers the CSV misses, the "4 CSV measures now resolve" list (which includes `crossings.csv` 356355973 @ 4494.61997946051) and the per-state tables. Since #274, fresh sends every route measure at 17 significant digits (`.frs_sql_exact()`), so these counts are not about what fresh sends.

The snapped positions are clamped to whole metres, which `format()` writes exactly when the chunk holds only whole numbers, so they are unaffected. The CSV measures and the 400-stream head-case sample are the ones in question.

## Proposed Solution

- Write the sweep's measures with `.frs_sql_exact()` (or `sprintf("%.17g", ...)`), and its keys with `%d`.
- Re-run the sweep against the same migrations and revise `research/fwa_point_snap.md` with the new counts, noting which ones moved.
- Found in the #274 plan review.


## Errors Encountered

| Error | Resolution |
|-------|------------|

## Smoke run, 2026-10-31 (caps: 300 PSCIS, 300 obs, 300 crossings, 5 + 5 expensive)

- The read-back guard on `working.tie266_measures_all` passes: RPostgres 1.4.10's
  `dbWriteTable()` round-trips the CSV doubles bit for bit.
- 345 of the 400 sampled blue lines have a guarded top (the #274 reviewer's 345).
- Head case, exact tops: 2 resolve in base, 331 under the tiebreak and under both. That
  matches the #274 reviewer's unpublished re-measure (old 2, new 331), now scripted.
- CSV misses on the capped sample: 32 base, 30 after. The full run gives the real counts.

## Plan review folded in (review-plan.md); second smoke run, 2026-10-31

- B1: each state now sends every CSV measure and top back as %.17g text and has
  PostgreSQL compare it with the stored double (`sent_exact()`); positions are asserted
  whole metres. Passes.
- G1: tops are max(upstream_route_measure) over every segment, since fwa_locatealong()
  has no guards. Smoke result (head case is full-size, 400): base 0 of 400 resolve,
  tiebreak / both 383 of 400; over the 341 lines whose top is a candidate segment's,
  0 -> 327. The guarded-top design gave 2 -> 331 of 345: its two base "hits" were lines
  whose guarded top sits below the line's real top, so they were never head cases.
- A2/A3: the head case has its own table (body) and `sweep_tops.csv` (one row per line);
  `summary` and `moved` keep the shape earlier runs had.
- G3: measures are written unquoted, so whole-metre rows do not churn.
