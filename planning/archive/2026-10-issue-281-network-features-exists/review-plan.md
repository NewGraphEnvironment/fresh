# Plan review — #281 (Plan agent, 2026-10-29 ~00:37 UTC, read-only; written here by the parent)

Findings, condensed from the reviewer's reply; disposition in findings.md.

- B1 aoi_filter is a full `WHERE` clause (R/frs_network_features.R:274): composes with a DISTINCT join, not with a correlated EXISTS on the upstream+aoi path.
- B2 NULL feature ids: array mode keeps a row with an empty array (FILTER), so "lengths > 0" != the array mode's row set; oracle and docs must pick one.
- G1 frs_db_query() returns a data.frame; `d$x <- TRUE` on a zero-row data.frame errors; mock returns a tibble so a zero-row test passes regardless.
- G2 no fixture with repeated segment ids; the dedupe mutation cannot go red on real data.
- G3 NULL segment ids: GROUP BY/DISTINCT give one NA row, EXISTS one per row; string_agg drops NULLs.
- G4 upstream live case should be required (upstream+aoi is the only path sending aoi_filter).
- G5 SETN oracle when the array form times out is unspecified.
- G6 put `result` last in the signature; test an invalid value.
- G7 title/description/@return describe arrays only.
- A1 a digest that unnests arrays skews timing; time end to end through the function as link sees it (transfer + R parse).
- A2 form chosen on the scoped path only; ships for aoi=NULL/upstream too.
- A3 DISTINCT still builds every pair; no success threshold for SETN.
- A4 shared scope means equality does not check the prefilter.
- O1 Phase 4 needs the script to capture the function's own exists SQL.
- O2 the "ids unchanged" check must compare against v0.46.0, not the modified function.
- Acceptance: zero-row mock vacuous (G1); prefilter mutation only visible to SQL-text tests; decision rule has no reps/margin/tie-break.
