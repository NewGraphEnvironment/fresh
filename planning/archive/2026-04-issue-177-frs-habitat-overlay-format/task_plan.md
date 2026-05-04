# Task: Drop frs_habitat_overlay format param; accept only canonical shape (#177)

`frs_habitat_overlay()` carries `format = c("wide", "long")` and
`long_value_col` for two source-table shapes that have no current
production consumer. Bcfishpass changed its authoritative CSV shape on
2026-04-26 to a third shape (row-per-(segment × species) with
per-habitat indicator columns) — that's the only shape link's pipeline
needs to consume.

PR #176's first attempt added a `species_col` parameter as an additive
third dispatch. That paper-over compounded the API. Cleaner answer:
drop `format` + `long_value_col` entirely. Hard-code the canonical
shape. Column names stay parameterized via `species_col`, `by`,
`habitat_types`. Callers with non-canonical sources transform first
(SQL view, R pivot, or link's forthcoming `lnk_ingest_bcfishpass()`).

## Phases

- [ ] Phase 1 — PWF baseline (this file + findings + progress)
- [ ] Phase 2 — Rewrite `frs_habitat_overlay()`: drop `format` + `long_value_col` from signature; require `species_col` (default `"species_code"`); single SQL dispatch path. Universal indicator coercion `lower(trim(<col>::text)) IN ('true', 't', '1')`. Update validation: `from` must contain `by` + `species_col` + each `habitat_types` column. Bridge mode retained (orthogonal to source shape).
- [ ] Phase 3 — Update `frs_habitat_overlay.Rd` doc + examples. New canonical-shape worked example. Document the transform-first pattern for non-canonical sources.
- [ ] Phase 4 — Drop tests for `format = "wide"` (suffix) and `format = "long"` paths. Keep + adapt the `species_col` integration tests as primary. Adjust mocks accordingly.
- [ ] Phase 5 — `/code-check` on staged diff
- [ ] Phase 6 — `devtools::test()` full suite — verify no regressions in non-overlay tests
- [ ] Phase 7 — NEWS entry + version bump 0.21.0 → 0.22.0 (breaking — pre-1.0; documented)
- [ ] Phase 8 — Force-push to overlay-species-col branch; update PR #176 title + body to reflect simplified scope; mark ready for review

## Critical files

- `R/frs_habitat_overlay.R` — rewrite signature + dispatch (drops ~100 lines net)
- `tests/testthat/test-frs_habitat_overlay.R` — drop wide-suffix + long-format tests; canonical-shape tests become primary
- `man/frs_habitat_overlay.Rd` — regenerated
- `NAMESPACE` — unchanged (no new exports)
- `NEWS.md`, `DESCRIPTION` — release artifacts

## Acceptance

- `frs_habitat_overlay()` signature has no `format`, no `long_value_col`
- `species_col` is a parameter with default `"species_code"`
- Single dispatch path: `WHERE k.<species_col> = '<sp>' AND lower(trim(k.<hab>::text)) IN ('true','t','1') AND additive_guard`
- All retained tests pass; dropped tests removed cleanly
- Bridge mode still works (verified by bridge-mode integration test, retained)
- `/code-check` clean
- NEWS + DESCRIPTION updated; PR #176 force-pushed and ready

## Risks

- **Existing test fixtures need rewriting**: tests previously using wide-suffix or long-format data must either be dropped (no current consumer) or rewritten to canonical shape. Audit each test's intent — if it tests overlay behavior generically, rewrite; if it tests a specific dropped path, drop.
- **Mock helpers** (`mk_dbq` etc.) are tied to wide-suffix expectations. Update or replace for canonical shape.
- **Link's call site is currently broken** against the new CSV. Coordinated update lands as the link follow-up PR. Until that lands, link's `tar_make()` won't run — acceptable, vignette is already pulled from the site.

## Not in this PR

- crate's `lnk_ingest_bcfishpass()` registry-driven canonicalization — separate impl-plan thread + PRs in link + crate
- link's call-site update — separate PR after fresh merges (small, targeted; bumps fresh dep to >= 0.22.0)
- `lnk_pipeline_classify.R` SQL pivot view (the temporary unblock I drafted earlier and reverted) — not needed; link will pass canonical-shape data or transform first
