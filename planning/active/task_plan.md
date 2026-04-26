# Task: Ingest known-habitat flags into fresh.streams_habitat

Companion to [link#55](https://github.com/NewGraphEnvironment/link/issues/55) — bcfishpass's published spawning/rearing classifications stitch model output (rule-based) WITH known habitat (manually-curated CSV → `streams_habitat_known`). link's pipeline today only emits the model side; the BABL SK comparison shows ~60 km of `csv_only` known habitat that bcfp picks up and we miss.

This issue scopes the **fresh-side helper** that link will call from `lnk_pipeline_classify` after `frs_habitat_classify` finishes.

## Goal

Provide `frs_habitat_known(conn, table, known, species, ...)` — a focused helper that ORs known-habitat boolean flags from a per-species lookup table INTO an existing `fresh.streams_habitat` table. Keeps fresh as the home for "habitat classification mechanics"; leaves the CSV loading / dimensions interpretation in link.

## Scope

- **In:** UPDATE-style SQL that flips `spawning`, `rearing`, `lake_rearing`, `wetland_rearing` from `FALSE → TRUE` on segments matching the known-habitat table for the given species.
- **In:** Per-species, per-habitat-type column mapping (same shape as bcfishpass `streams_habitat_known`).
- **In:** Tests (unit + integration on fixture).
- **Out:** Loading user_habitat_classification.csv → `<schema>.user_habitat_classification` (link's job, already exists).
- **Out:** Calling the new helper from `lnk_pipeline_classify` (separate link PR).
- **Out:** Reverse direction (CSV-says-FALSE overriding model-says-TRUE) — known habitat is purely additive.

## API shape (match existing fresh conventions)

```r
frs_habitat_known(conn,
                  table,            # fresh.streams_habitat to update in place
                  known,            # schema-qualified known-habitat table
                  species = NULL,   # NULL = all; otherwise vector of codes
                  habitat_types = c("spawning", "rearing",
                                    "lake_rearing", "wetland_rearing"),
                  verbose = TRUE)
```

Mirrors `barrier_overrides` parameter naming + `frs_habitat_classify` signature style.

## Phases

- [x] Phase 1 — PWF baseline (this file + findings.md + progress.md)
- [x] Phase 2 — Decide known-table column convention (per-species columns vs long-format)
- [x] Phase 3 — Implement `frs_habitat_known()` in `R/frs_habitat_known.R`
- [x] Phase 4 — Robust unit tests (mocked SQL; column mapping; verbose; edge cases)
- [x] Phase 5 — Integration test on small fixture (real DB; flips a known segment from FALSE → TRUE)
- [x] Phase 6 — Add to NAMESPACE via roxygen `@export`
- [x] Phase 7 — `devtools::document()` + lintr clean
- [ ] Phase 8 — `/code-check` on staged diff (per session-start instruction)
- [x] Phase 9 — Full `devtools::test()` via rtj harness — 749 PASS / 0 FAIL / 13m20s
- [x] Phase 10 — NEWS entry + version bump → 0.18.0
- [ ] Phase 11 — PR to fresh

## Critical files

- `R/frs_habitat_known.R` (new — the helper)
- `R/frs_habitat_classify.R` (read-only — for naming/structure consistency)
- `R/utils.R` (read-only — for `.frs_db_execute`, `.frs_quote_string`, `.frs_validate_identifier`)
- `tests/testthat/test-frs_habitat_known.R` (new — unit + integration)
- `NEWS.md` + `DESCRIPTION` (final commit before PR)

## Verification / acceptance

- Unit tests cover: column-name escape, NULL species → all, species filter, missing column → error, verbose output, no-op when known is empty.
- Integration test confirms a known segment flips on a small fixture.
- `devtools::test()` passes full suite (722 → 722 + N new).
- link integration path (separate PR) confirms BABL SK spawning under bcfishpass bundle rises to ~132 km (matching `streams_habitat_linear.spawning_sk > 0`).

## Risks

- **Column-mapping mismatch.** bcfishpass `streams_habitat_known` has `spawning_sk`, `rearing_sk`, etc. link's `user_habitat_classification.csv` has the same shape. Ensure helper handles missing per-species columns gracefully (e.g. `spawning_pk` may not exist if PK doesn't have known habitat).
- **Idempotency.** Running twice should produce same result (UPDATE with OR semantics is idempotent).
- **Schema surface.** Don't proliferate new public helpers if link's caller is the only client. If fresh-internal sufficient, keep `.frs_*` private; export only when reuse outside link is plausible. **Decision:** export — the API is generally useful for any caller stitching observation-based habitat into a model-based classification.

## Not in this PR

- link#55's caller — separate PR on link.
- bcfishpass's secondary `streams_habitat_known` semantics (multi-tier `spawning_sk = 1/2/3`). Our function ORs in TRUE; if bcfishpass-style tier values are needed later, that's a follow-up.
