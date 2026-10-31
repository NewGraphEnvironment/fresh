# Code-check round 1: branch 289 (git diff 7bfd156...HEAD)

## Checklist read

- code-check.md: the prose of all 14 H3s under `## Mechanisms` (table rows skipped). Not read: the 14 "Rules that stand alone", the 6 Security and the 3 Spreadsheets/PDFs headings (23 in all; index only).
- code-check-r.md: read 11 sections. "`on.exit()` at a script's top level never fires", "A `data-raw/` script must load the source tree…", "A database driver's value is not a base R type…", "A value compared as `::text` in SQL has PostgreSQL's spelling…", "`identical()` on two reader results…", "`vapply(..., USE.NAMES = FALSE)`…", "`as.integer("NaN")`…", "Postgres row order is never fixed…", "`sprintf("%g", x)` writes `Inf` and `NA`…", "An `information_schema` lookup…", "Rscript reads a script as it runs…". Not read: the other 104 of 115 (index only).
- code-check-shell.md: index only, 70 of 70 not read. No shell is in the diff.
- code-check-spatial.md: index only, 94 of 94 not read. The diff uses no sf, terra or GDAL. I checked the FWA measure claims against the database directly.
- code-check-infra.md: index only, 38 of 38 not read. The Docker/Postgres headings don't apply to read-only SELECTs.

## Findings

- **[severity: bug]** research/fwa_point_snap.md:11, :42, :50, :75; data-raw/point_snap_tie_sweep.R:43-44, :384-386; planning/active/findings.md:1-14, :63, :76 (and the #289 issue body). The diff blames the old error on 7 significant digits. That mechanism is wrong. The old `chunked()` called `format(d$m, scientific = FALSE)` once over the whole `d` before it split the chunks. `format()` uses one decimal count for the vector, set by the element that needs the most decimals to show 7 significant digits. Over the 23,540 CSV measures that count is **11 decimals**. So measures went out at 14 to 16 significant digits, rounded to 1e-11 m, not at 7. They did not go out "per chunk" (research:11) either.
  - I rebuilt the old text by the same md5 sample and the same `ORDER BY src, id`. The DB-side rank of crossings_365234 is 11097, which matches my rebuild.
  - crossings_108527 went out as `4494.61997946051`, exactly, not `4494.620`. The old sweep.txt's `4494.620` was `print()` showing the stored double at 7 digits. It was never the text sent.
  - 957.70485427024903 went out as `957.70485427025`, not `957.7049` (research:75; findings:76 measured `format()` on a scalar, not on the vector the sweep formatted).
  - I replayed the old and new text through base `fwa_locatealong()` in a READ ONLY transaction. Script: `/private/tmp/claude-501/-Users-airvine-Projects-repo-fresh/1131ec99-e8dc-43f4-be62-8dad0c8e2dd8/scratchpad/probe/old_vs_new.R`. It reproduces **42** base misses with the old text and **36** with the new. The 6 that flip (crossings_201521, _466175, _525000, _8913, _96415, falls_699) all moved by about 1e-12 m.
  - So every count in the note is right: 42/38/38, then 36/31/31, net 6 and 7, and one hidden mover. Only the stated cause and size of the rounding are wrong. The fix is wording: "format() over the whole vector, which here wrote 11 decimal places". The NEWS correction in the PR body should not repeat "7 digits".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" ; code-check.md "One fact derived twice"

- **[severity: bug]** research/fwa_point_snap.md:74 (and planning/active/findings.md:61-63). The note says 957.70485427024903 "is exactly the top of segment 702605415". It is not.
  - The stored `upstream_route_measure` is 957.7048542702494, which is 957.70485427024937 at %.17g.
  - `upstream_route_measure = 957.70485427024903::float8` is false, and the difference is 3.41e-13 (3 ULPs). Checked by psql.
  - The CSV holds `957.704854270249`, which is the top written at 15 significant digits. That reads back 3 ULPs *below* the top, inside the segment.
  - The old run's `957.70485427025` is 6.3e-13 *above* the top, in the 0.5 mm gap to 957.705341846863. That is why the old run missed it in every state. Base still misses the exact value because `round(us,4) = round(m,4) = 957.7049`.
  - So "a measure in effect at the top, missed by the 4-decimal rule" is true, but "exactly the top" and "At 7 digits it is 957.7049" are not. The real mechanism (15-digit text, then 11-decimal rounding past the end) is the fresh#274 mechanism, and is worth saying.
  - **Rule:** code-check.md "The probe is broken before the world is"

- **[severity: fragile]** data-raw/point_snap_tie_sweep.R:387-389 vs :461-470, :508-515. `sent_exact()` does not check the text `chunked()` sends. It builds its own copy with `vapply(d$m, .frs_sql_exact, …)`, while `chunked()` builds its `vals` in a separate expression.
  - If `chunked()` went back to `format()` (the #289 defect), `sent_exact()` would still pass.
  - So the comment at :510-511 ("This covers the read, the format and the parse in one check (#289)") claims more than the guard does. It covers the RPostgres read and `.frs_sql_exact()`, not the formatter the sweep actually uses.
  - The fix is to build the measure text in one place (a helper both call, or `chunked()` returning the `vals` it sent for `sent_exact()` to compare).
  - **Rule:** code-check.md "Restore the bug and prove the guard fires" ; code-check.md "Verification that reads its own output"

Checked and consistent with the logs and the code:

- The head-case figures: 400 / 341 / 345, 4 with the guarded top below the line's top, 0→383, 0→327, 17 and 14.
- The 5 CSV movers.
- 85→86 watershed misses, and 294 errors (293 + 1).
- The base md5 matches the old run, and sweep_errors.csv is unchanged.
- The test comment's 0/383, and head_blk 360447231 having equal guarded and unguarded tops (sweep_tops.csv row 311).

One more note, not a defect: research:67's "2 before" for 359014708 and 359017843 comes from a hand query, not from the committed logs. I re-checked it read-only and it is true: both resolve on base at their candidate top.
