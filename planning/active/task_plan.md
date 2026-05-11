# Task: frs_point_match: match two point datasets along FWA network within instream distance (#206)

fresh has primitives for snapping points to FWA streams (`frs_point_snap`) and for finding upstream/downstream features per segment (`frs_network_features`), but no primitive for matching two **point datasets** along the network within a distance threshold.

Concrete use case driving this: link's bcfp parity layer needs to reproduce bcfp's `02_pscis_streams_150m.sql` at `smnorris/bcfishpass@v0.7.14-125-g6e9cf1c` (current tunnel state, `bcfishpass.log.model_run_id=121` rebuilt 2026-05-05) — match PSCIS crossings to modelled crossings within 100m instream distance on the same stream, then keep the nearest PSCIS per modelled crossing. Currently link's `lnk_pipeline_crossings` is missing this layer, leaving modelled crossings duplicating PSCIS positions in the working schema; cascades into >+1000 false-positive anthropogenic barriers in BULK alone (see link's `research/bcfp_table_map.md`).

## Phase 1: scaffold + R/frs_point_match.R

- [ ] Read `R/frs_network_features.R` end-to-end as the template (the right v0.29.0+ template with per-side overrides, identifier validation pattern, sprintf composition)
- [ ] Read `R/utils.R` to find `.frs_validate_identifier()` and other private helpers
- [ ] Verify bcfp algorithm unchanged between local v0.7.13 source and tunnel v0.7.14-125 (already done — `git log` shows no commits to `02_pscis_streams_150m.sql` between those refs)
- [ ] Write `R/frs_point_match.R`:
  - Signature per Approach (see `/Users/airvine/.claude/plans/snuggly-fluttering-hopper.md`)
  - Input validation: identifier sanitization for `table_a`, `table_b`, `table_to`, `table_a_id_col`, `table_b_id_col`; numeric+positive check for `distance_max`
  - SQL composition via sprintf template
  - `frs_db_query()` or equivalent execute (no return value needed)
  - Returns `invisible(conn)`
  - Roxygen: `@family network`, `@export`, `@examples \dontrun{}`, NOT documented stream-name scoring (out of scope)

## Phase 2: tests/testthat/test-frs_point_match.R

- [ ] Tier 1 — validation tests (no DB): each arg validation path triggers `expect_error()`. Mirror the structure of `tests/testthat/test-frs_network_features.R` lines 6–124.
- [ ] Tier 2 — SQL composition tests (mocked `frs_db_query` via `withr::local_mocked_bindings`): capture the SQL string, `expect_match` for the key clauses (`DISTINCT ON`, `ABS(... - ...) < <n>`, `blue_line_key = blue_line_key`, schema-qualified table refs). Mirror `test-frs_network_features.R` lines 127–374.
- [ ] Tier 3 — live DB integration test (`skip_if_not(.frs_db_available())`): create two small test point tables, run frs_point_match, verify expected matches and NULLs.

## Phase 3: live byte-identical validation against bcfp

- [ ] Run `frs_point_match` against `bcfishpass.pscis_assessment_svw` (filtered to ADMS) and `bcfishpass.modelled_stream_crossings` (filtered to ADMS), with `distance_max = 100`.
- [ ] Diff result vs `bcfishpass.pscis_streams_150m` for ADMS rows where `modelled_xing_dist_instream < 100` (the rows that would survive our 100m filter).
- [ ] Acceptance: every (stream_crossing_id, modelled_crossing_id) pair in our output matches bcfp's output. Document the diff in `tests/integration/` or PR body.
- [ ] Note: bcfp's `pscis_streams_150m` is a SCORING table (keeps multiple matches with name/width scores). Our output is the deduped subset (one match per PSCIS per stream). The byte-identical claim is on the final pairing, not the intermediate scoring.

## Phase 4: release

- [ ] DESCRIPTION: 0.29.0 → 0.30.0 (minor bump per R-package conventions — new exported function)
- [ ] NEWS.md: 0.30.0 entry — `frs_point_match` description + closes #206
- [ ] `devtools::document()` to regenerate NAMESPACE + man/
- [ ] `devtools::check()` clean (no ERROR/WARNING; pre-existing NOTEs OK if unchanged)
- [ ] `lintr::lint_package()` clean
- [ ] PR body cites the link parity context (link#154 consumes this primitive)

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
