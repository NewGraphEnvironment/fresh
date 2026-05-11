# Task: frs_candidates_pick: score + filter + dedup candidates per key (#207)

When matching point datasets along the FWA network, a single "key" entity (a PSCIS crossing, an observation, a field-assessed crossing) can have multiple candidate matches in another table. Picking the best candidate often requires more than distance — it requires column-to-column comparisons against shared attributes that disambiguate beyond pure geometry: stream name, watershed group, stream order, channel width, species code, observer name, etc.

`frs_candidates_pick` is the missing primitive. Combined with `frs_point_snap(num_features = N)` upstream and `frs_point_match` downstream, the bcfp PSCIS-build algorithm reproduces byte-identically via composition.

## Phase 1: scaffold R/frs_candidates_pick.R

- [ ] Read `R/frs_point_match.R` (just-shipped v0.30.0) one more time as the immediate-template — the SQL composition shape, validation pattern, and ID-introspection guard are directly reusable.
- [ ] Write `R/frs_candidates_pick.R`:
  - Signature per Approach above
  - Input validation: `.frs_validate_identifier()` for `table_in`, `table_to`, `col_key`. Required-args checks for `order_by`. `exp_score` / `exp_filter` are nullable strings; when supplied, just length-1 character checks (caller writes the SQL — we don't validate its inside).
  - Reserved-column collision: when `exp_score` is set, the output has a `score` column. Guard against `table_in` already having a `score` column (similar to fresh#206's distance_instream guard).
  - SQL composition via `sprintf` template
  - `.frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", table_to))` first, then the CTE+SELECT
  - Returns `invisible(conn)`
  - Roxygen: `@family network` (sibling to frs_point_snap, frs_point_match), `@export`, `@examples \dontrun{}` covering bcfp PSCIS-to-stream case + a more generic case (observations dedup or similar)
- [ ] `devtools::document()` to regenerate man page + NAMESPACE export
- [ ] `lintr::lint("R/frs_candidates_pick.R")` clean

## Phase 2: tests/testthat/test-frs_candidates_pick.R

- [ ] Tier 1 — validation tests (no DB): required args, identifier sanitization rejection, reserved-column collision check.
- [ ] Tier 2 — SQL composition tests via `withr::local_mocked_bindings` on `.frs_db_execute` + `.frs_table_columns` — mirrors `tests/testthat/test-frs_point_match.R` structure.
  - `expect_match` on key clauses: DROP + CREATE, `WITH scored AS`, `SELECT DISTINCT ON (col_key)`, score expression appearing as a derived column, ORDER BY containing col_key first then caller's clauses.
  - `expect_no_match` when `exp_score = NULL` → no `WITH scored` CTE.
  - `expect_no_match` when `exp_filter = NULL` → no `WHERE` clause.

## Phase 3: live byte-identical validation against bcfp

- [ ] Stage a candidates table for BULK PSCIS:
  1. Use `frs_point_snap` against `bcfishpass.pscis_points_all` (raw PSCIS) with `num_features = N` and `tolerance = 150` to get multi-stream candidates.
  2. JOIN with `whse_fish.pscis_assessment_svw` (for `stream_name`) and `whse_basemapping.fwa_stream_networks_sp` (for `gnis_name`, `stream_order`, etc.) to enrich the candidates table with score-bearing columns.
- [ ] Call `frs_candidates_pick` with bcfp's name-match scoring expression (extract from `bcfp/04_pscis.sql`):
  ```r
  exp_score = "CASE
    WHEN normalize_name(stream_name) = normalize_name(gnis_name) THEN 100
    WHEN stream_name IS NULL OR gnis_name IS NULL THEN 0
    ELSE -100
  END"
  ```
  Then compare the picked (stream_crossing_id, linear_feature_id) pairs against `bcfishpass.pscis.linear_feature_id` for BULK.
- [ ] Acceptance: ≥99% match on BULK PSCIS-to-stream selection (closes the 5-diff gap from fresh#206 BULK validation).
- [ ] If the bcfp `name_match` normalization is complicated (creek-abbreviation handling), document the divergence vs raw SQL string equality — exp_score is caller-defined; this is where caller-specific cleanup lives.

## Phase 4: release

- [ ] Update link/CLAUDE.md to add the `exp_<role>` parameter convention alongside the existing `table_<role>` and `col_<role>` rules. SQL-expression params (`exp_score`, `exp_filter`, future `exp_where`, `exp_select`, etc.) prefix `exp_` for autocomplete grouping. Separate commit on link main.
- [ ] DESCRIPTION 0.30.0 → 0.31.0 (minor bump — new exported function)
- [ ] NEWS.md 0.31.0 entry covering: semantics, composition with `frs_point_snap` + `frs_point_match`, BULK validation result, first consumer (link#154 will rewire to use this chain)
- [ ] `devtools::document()` regenerates NAMESPACE + man/
- [ ] `devtools::check()`: 0 errors / pre-existing warnings/notes only (verify identical to main pre-PR)
- [ ] `lintr::lint_package()` clean for the new R file
- [ ] PR body covers semantics, composition story, BULK validation numbers, link#154 as the downstream consumer

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
