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
