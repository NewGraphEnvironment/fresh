# Task: frs_point_match: match two point datasets along FWA network within instream distance (#206)

fresh has primitives for snapping points to FWA streams (`frs_point_snap`) and for finding upstream/downstream features per segment (`frs_network_features`), but no primitive for matching two **point datasets** along the network within a distance threshold.

Concrete use case driving this: link's bcfp parity layer needs to reproduce bcfp's `02_pscis_streams_150m.sql` at `smnorris/bcfishpass@v0.7.14-125-g6e9cf1c` (current tunnel state, `bcfishpass.log.model_run_id=121` rebuilt 2026-05-05) — match PSCIS crossings to modelled crossings within 100m instream distance on the same stream, then keep the nearest PSCIS per modelled crossing. Currently link's `lnk_pipeline_crossings` is missing this layer, leaving modelled crossings duplicating PSCIS positions in the working schema; cascades into >+1000 false-positive anthropogenic barriers in BULK alone (see link's `research/bcfp_table_map.md`).

## Phase 1: scaffold + R/frs_point_match.R

- [x] Read `R/frs_network_features.R` end-to-end as the template (the right v0.29.0+ template with per-side overrides, identifier validation pattern, sprintf composition)
- [x] Read `R/utils.R` to find `.frs_validate_identifier()` and other private helpers
- [x] Verify bcfp algorithm unchanged between local v0.7.13 source and tunnel v0.7.14-125 (already done — `git log` shows no commits to `02_pscis_streams_150m.sql` between those refs)
- [x] Write `R/frs_point_match.R`:
  - Signature per Approach (see `/Users/airvine/.claude/plans/snuggly-fluttering-hopper.md`)
  - Input validation: identifier sanitization for `table_a`, `table_b`, `table_to`, `table_a_id_col`, `table_b_id_col`; numeric+positive check for `distance_max`
  - SQL composition via sprintf template
  - `.frs_db_execute()` (no return value needed — DDL)
  - Returns `invisible(conn)`
  - Roxygen: `@family network`, `@export`, `@examples \dontrun{}`, NOT documented stream-name scoring (out of scope)

## Phase 2: tests/testthat/test-frs_point_match.R

- [x] Tier 1 — validation tests (no DB): each arg validation path triggers `expect_error()`. Mirror the structure of `tests/testthat/test-frs_network_features.R` lines 6–124.
- [x] Tier 2 — SQL composition tests (mocked `.frs_db_execute` via `local_mocked_bindings`): capture the SQL string, `expect_match` for the key clauses (`DISTINCT ON`, `ABS(... - ...) < <n>`, `blue_line_key = blue_line_key`, schema-qualified table refs). Mirror `test-frs_network_features.R` lines 127–374.
- [ ] Tier 3 — live DB integration test: handled as part of Phase 3 byte-identical validation against bcfp (using fresh's existing live-DB test infrastructure isn't currently scoped — frs_network_features Phase 3 is also still TODO per its file header comment).

## Phase 3: live byte-identical validation against bcfp

- [x] Run `frs_point_match` against `bcfishpass.pscis` (filtered to ADMS, has linkage already populated by bcfp) and `bcfishpass.modelled_stream_crossings` (filtered to ADMS), with `distance_max = 100`.
- [x] Diff result vs `bcfishpass.pscis.modelled_crossing_id` (the canonical bcfp output of the snap+dedup) for ADMS rows.
- [x] **Acceptance met: 60 / 60 (stream_crossing_id, modelled_crossing_id) pairs identical. 0 in ours-not-ref. 0 in ref-not-ours.**
- [x] Note: bcfp's `pscis_streams_150m` is a SCORING intermediate (multiple matches per PSCIS pre-dedup). The canonical post-dedup linkage lives on `bcfishpass.pscis.modelled_crossing_id`. Our output is the deduped subset — byte-identical to that.

### Live test script

Captured at `/tmp/fresh_206_live_validation.R` for the PR body — runs against the bcfp tunnel, stages PSCIS+modelled subsets for ADMS, calls frs_point_match, diffs result vs `bcfishpass.pscis.modelled_crossing_id`.

## Phase 4: release

- [x] DESCRIPTION: 0.29.0 → 0.30.0 (minor bump per R-package conventions — new exported function)
- [x] NEWS.md: 0.30.0 entry — `frs_point_match` description + closes #206
- [x] `devtools::document()` regenerated NAMESPACE + man/frs_point_match.Rd + frs_network_features.Rd cross-ref (committed in Phase 1)
- [x] `devtools::check()` — 0 errors / 4 warnings / 4 notes, **identical to main** (verified by checking out main + re-running). Zero new check issues introduced.
- [x] `lintr::lint("R/frs_point_match.R")` clean (zero lints).
- [ ] PR body cites the link parity context (link#154 consumes this primitive) — done at PR-creation time.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
