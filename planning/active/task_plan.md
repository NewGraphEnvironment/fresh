# Task: frs_network_features — direction-agnostic per-segment feature-array primitive (#201)

A recurring pattern in stream-network analysis: for each segment in a network table, return an array of point features (snapped to FWA via `(blue_line_key, drm, wscode_ltree, localcode_ltree)`) that lie at a particular relative position. bcfp's `bcfishpass.load_dnstr_chunked` UDF solves the downstream slice DB-side; fresh has the right home for the R-side primitive (sibling to `frs_network_*`) but the function doesn't exist yet.

First consumer: link's `lnk_pipeline_access` (link#124, in flight, currently blocked on this primitive). Future consumers: water-quality station roll-ups, fish-survey aggregations, sediment-sample summaries.

Naming + design (settled with user):

- `frs_network_features` — fits `frs_network_*` family. Distinct shape from siblings: segments→features (per-segment arrays), not point→segments.
- `direction = c("downstream", "upstream")` — required, no default; `match.arg()`.
- `aoi = NULL` — forward-compat. MVP only validates WSG codes; polygon/ltree later via `.frs_resolve_aoi`.
- `segments` / `features` — table args (not `from`/`to` — avoids implying a fixed direction).
- `segment_id_col` (default `"id_segment"`) / `feature_id_col` (no default — caller passes column name).
- `include_equivalents = FALSE` — mirrors bcfp.
- Output: 2-column tibble `(<segment_id_col>, feature_ids)`. `feature_ids` is `text[]`; **NULL when zero matches** (don't synthesise empty arrays — keep Postgres semantics).
- Exported. Public.

## Phase 1: Function signature + validation + roxygen + NAMESPACE (~0.5 day)

- [ ] Create `R/frs_network_features.R` with full signature, arg validation via `.frs_validate_identifier` (from `R/utils.R`), `match.arg(direction)`, and `aoi` validation (WSG-code regex `^[A-Z]{3,5}$` for now; document polygon/ltree as future-compat).
- [ ] Roxygen with worked `\dontrun{}` example showing both directions + a generic non-barrier use case (e.g. water-quality stations).
- [ ] Body returns a not-implemented `stop()` for now (or a trivial placeholder query) so the function exists in the namespace but doesn't run real SQL yet. Lets tests of validation alone pass.
- [ ] `devtools::document()` updates `NAMESPACE` + `man/frs_network_features.Rd`.
- [ ] `tests/testthat/test-frs_network_features.R` — validation-only tests (missing `feature_id_col` errors; bad identifier characters error; bad direction errors; bad aoi format errors).
- [ ] `devtools::test()` green; `lintr::lint_package()` clean.
- [ ] Commit (Phase 1 done, atomic with checkbox flip).

## Phase 2: SQL implementation (both directions) + mocked unit tests (~0.5 day)

- [ ] Fill in SQL builder. Pattern based on bcfp's `load_dnstr_chunked.sql`:
  - `LEFT JOIN` segments to features on `whse_basemapping.fwa_<direction>(a.<keys>, b.<keys>, <include_equivalents>, 1)`.
  - `array_agg(b.<feature_id_col> ORDER BY b.wscode_ltree DESC, b.localcode_ltree DESC, b.downstream_route_measure DESC) FILTER (WHERE b.<feature_id_col> IS NOT NULL)`.
  - `aoi` becomes a `WHERE a.watershed_group_code = <aoi>` clause when set.
- [ ] Use `frs_db_query()` (from `R/frs_db_query.R`) for execution — mirrors `frs_network_downstream`'s pattern.
- [ ] Mocked unit tests (`local_mocked_bindings(frs_db_query = ...)`):
  - "downstream" direction: SQL contains `fwa_downstream(...)` and the segments-first/features-second arg order.
  - "upstream" direction: SQL contains `fwa_upstream(...)` with same arg order.
  - `aoi = "ADMS"` injects `WHERE a.watershed_group_code = 'ADMS'`.
  - `include_equivalents = TRUE` produces `true` in the SQL; default produces `false`.
  - Returned tibble preserves the `segment_id_col` name verbatim.
- [ ] `/code-check` on staged diff.
- [ ] Commit (Phase 2 done).

## Phase 3: Live parity test against bcfp tunnel (~0.5 day)

- [ ] Add a skippable integration test `tests/testthat/test-frs_network_features-live.R` guarded by `skip_if(Sys.getenv("PG_PASS_SHARE") == "")`.
- [ ] Runs `frs_network_features(conn, "bcfishpass.streams", "bcfishpass.barriers_pscis", segment_id_col = "segmented_stream_id", feature_id_col = "barriers_pscis_id", direction = "downstream", aoi = "ADMS")` against the bcfp tunnel (`localhost:63333`, db `bcfishpass`, env-var auth).
- [ ] Compares to `bcfishpass.streams_dnstr_barriers.barriers_pscis_dnstr` filtered to ADMS via `inner join`. Asserts row count match + per-segment array equality after `sort()` on both sides.
- [ ] Acceptance: 100 % byte-identical (mod sort) on ADMS. The earlier scratch attempt got 15613 / 15647 — the LATERAL pattern was lossy. Pure `LEFT JOIN`+`array_agg` with the bcfp `ORDER BY` should match exactly.
- [ ] Repeat the same test for `direction = "upstream"` against `bcfishpass.streams_upstr_observations` if a clean reference exists; otherwise skip (parity question is downstream-only for the immediate consumer).
- [ ] Commit (Phase 3 done).

## Phase 4: Release (~0.5 day)

- [ ] `NEWS.md` 0.28.0 entry (additive new exported function = minor bump under R-package conventions).
- [ ] `DESCRIPTION` 0.27.6 → 0.28.0.
- [ ] PR body: closes #201, includes the ADMS parity numbers from Phase 3 in the test plan section.
- [ ] After merge: `/planning-archive` on fresh side, then `cd ~/Projects/repo/link` to resume link#124 Phase 2 — the consumer wiring that was blocked on this primitive.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
