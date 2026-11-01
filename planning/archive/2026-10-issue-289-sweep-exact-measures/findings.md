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

## Full run, 2026-10-31 (20:45:55 -> 21:48:37 UTC; states 1323 / 1263 / 1161 s)

- Header: migration md5s match the 2026-10-27 run; rollback confirmed; base-side md5
  `f0a5e96f60dd7a7af0eddc1e165faf48` reproduces, so the 49,725 positions are identical.
- Unchanged: positions 0 misses every state; expensive 85 -> 86 watershed misses, 294 ->
  293 errors; 2 empty traces; `sweep_errors.csv` byte-identical.
- CSV locatealong misses: base 42 -> **36**, tiebreak / both 38 -> **31**. Net change from
  the migration is now 5, not 4.
- Newly moved: `crossings.csv` 356312469 @ 957.70485427024903. It is exactly the top of
  segment 702605415 (us 957.7048542702494), with the next segment starting at
  957.705341846863, a 0.5 mm gap: an interior head case. At 7 digits it went out
  rounded into the gap and missed in every state. Checked by hand on base: 0 rows.
- Head case (400 lines, own top over every segment): 0 -> 383 resolve; over the 341 whose
  top is a candidate segment's, 0 -> 327. 17 / 14 still miss after the migration.
- `head_blk` 360447231: guarded and unguarded tops equal (1528.8506958829107), so the
  gate pin is unaffected.
- `sweep_summary.csv`'s old header ended in CRLF; R writes LF, so that line diffs with
  identical text.

## The "2 before" explained (2026-10-31)

Same 400 lines, candidate-segment top: 345 tops; 4 sit below the line's real top, and 2 of
those (359014708, 359017843) resolve on base, since a later segment holds the measure. That
is #266's "2 before". `format(957.70485427024903)` is `957.7049`, in the 0.5 mm gap.

## Code-check round 1 corrected the issue's premise (2026-10-31, review-round1.md)

- The old `chunked()` called `format()` once over the whole frame. For the 23,540 CSV
  measures that shares **11 decimals** (14-16 significant digits), not 7: reproduced with
  `format()` over the CSV measure vector. `format(x)` on ONE value gives 7 digits, which is
  where the issue's `4494.620` came from; the old `sweep.txt`'s `4494.620` was `print()`.
- So the 2026-10-31 entries above saying "7 digits" / `957.7049` are wrong in the cause and
  size of the rounding; the counts are right. 957.70485427024903 is 3.4e-13 m below the
  stored top 957.70485427024937 (psql `=` false), not on it; the old text
  `957.70485427025` was 6.3e-13 m above it, in the gap.
- `sent_exact()` built its own text; it now checks `chunked()`'s returned `sent`. Mutant
  (format() restored in chunked()) stops: "3840 of 3840 rows joined and 1332 differ".
  Real script passes the smoke run. The committed full-run logs stand: the fix moves the
  check, not the text sent.

## Code-check round 3: mechanism and enumeration (2026-10-31, review-round3.md)

Mechanism: claims about a population or about fwapg's behaviour taken from something other
than the population or fwapg (one short vector, decimal text, a reviewer's wording, an
issue's headline). Round 3 enumerated 56 numeric / quantified claims in the changed prose;
5 did not hold and were fixed. Each replacement re-measured here:
- 400 tops at 15 digits: 188 above the stream's end, 182 below, 30 exact (psql,
  `extra_float_digits = 0`, over sweep_tops.csv's own text).
- `957.70485427025` parses 6.821e-13 m above segment 702605415's top (psql). The note no
  longer asserts why the migrated function misses it ("in the gap" was round 1's
  unrun explanation); it states only that it lies past the segment's last measure.
- "rounded about half the CSV measures": 12,260 of 23,540, measured with psql's parse.
- `frs_wsg_drainage()` writes via `dbQuoteLiteral()` (R/frs_wsg_drainage.R:101).
