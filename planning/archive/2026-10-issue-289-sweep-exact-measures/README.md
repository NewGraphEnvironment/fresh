## Outcome

`data-raw/point_snap_tie_sweep.R` wrote its `VALUES` measures with one `format()` call over
the whole frame, which shares one decimal count across the vector (11 decimals for the
CSV measures, not the 7 significant digits the issue first said: `format()` gives 7 only
on a short vector). It now sends `.frs_sql_exact()` text and keys through `%d`; each state
has PostgreSQL compare the text `chunked()` actually sent with the stored double
(`sent_exact()`, proven to fire against a copy with `format()` restored). The head case
is now scripted (400 blue lines, each sent at its own top over every segment, written to
`sweep_tops.csv`), replacing #266's unrecorded "2 before, 218 after". The sweep was re-run
against the same migrations and `research/fwa_point_snap.md` revised from it.

What was learned: the review rounds kept finding claims taken from something other than
the population they described (one short vector, decimal text, a reviewer's wording, an
issue headline). Round 3 ended the loop by enumerating all 56 numeric and quantified
claims in the changed prose and re-measuring each replacement.

## Measurement

Re-run 2026-10-31 (states 1323 / 1263 / 1161 s), against the 2026-10-27 run:

- CSV `fwa_locatealong()` misses: base 42 -> **36**, after the tiebreak migration 38 -> **31**.
  The old rounding moved 12,260 of 23,540 CSV measures by at most 5e-12 m (PostgreSQL's
  parse), which was enough to move a net 6 / 7 measures across a segment boundary.
- Five CSV measures now resolve, not four. The added one, `crossings.csv` 356312469 @
  957.70485427024903, sits 3.4e-13 m below segment 702605415's top; the old text parsed
  6.8e-13 m above it and missed in every state.
- Unchanged, as a whole-metre input must be: 49,725 snapped positions (base-side md5
  `f0a5e96f…` reproduces), watershed 85 -> 86 misses, 294 -> 293 errors, 2 empty traces.
- Head case: **0 of 400** blue lines resolve their own top before the migration, **383**
  after; over the 341 whose top is a candidate segment's, 0 -> 327. The guarded-top
  variant gives 2 -> 331 of 345, and its two "before" hits are not head cases: a later
  segment holds the measure. At 15 digits, 188 of the 400 tops round above the stream's
  end, 182 below it, 30 exactly.
- Wrong turns kept: the plan used a guarded top (plan review G1 moved it); round 1
  overturned the issue's 7-digit premise; round 2 overturned round 1's "14 to 16 digits";
  round 3 overturned round 1's "in the gap" explanation, which no run had tested.

Durable verdicts: [research/fwa_point_snap.md](../../../research/fwa_point_snap.md).

## Evidence

`data-raw/logs/indexpoint_266/sweep*` (previous run: `git show 7bfd156:data-raw/logs/indexpoint_266/<file>`).

Closed by: PR (opened from branch `289-point-snap-tie-sweep-r-sends-measures-at`)
