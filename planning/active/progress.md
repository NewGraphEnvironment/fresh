# Progress — frs_network_features (#201)

## Session 2026-05-05

- Plan-mode exploration with user feedback led to a substantially tighter design than the earlier scratch:
  - direction-agnostic (one function, `direction` required, no default) instead of two functions.
  - `aoi` instead of `wsg` (forward-compat — accepts polygon/ltree later via `.frs_resolve_aoi`).
  - Public exported (`frs_network_features`) — diamond not hidden as private link helper.
  - NULL arrays for zero-match segments (don't fight Postgres semantics).
- Earlier scratch (`R/frs_dnstr_features.R` on deleted branch `frs-dnstr-features-primitive`) had a lossy `LEFT JOIN LATERAL` pattern (15613/15647 ADMS match). Phase 2 will use plain `LEFT JOIN` + `array_agg` matching bcfp's `load_dnstr_chunked.sql` for byte-identical parity.
- fresh main got a small housekeeping commit (54dfb92) tracking previously-untracked `scripts/habitat/habitat_benchmark_island.R` + `habitat_province.R` + their April logs — kept the feature branch clean of scope-creep.
- Created branch `201-frs-network-features-per-segment-feature` off main.
- Scaffolded PWF baseline (task_plan.md, findings.md, progress.md) with approved 4-phase breakdown.
- Driver of this work: this session is in `~/Projects/repo/link` but driving fresh#201 from here per user directive ("we just do it here vs switch to fresh handling business").
- Phase 1 done: `R/frs_network_features.R` shipped with full signature, validation, roxygen examples (downstream + upstream + generic water-quality use case), and stub `stop()` body for Phase 2 to fill. NAMESPACE + Rd updated by document(). 11 / 11 validation tests pass; lintr clean.
- Phase 2 done: SQL builder filled in. `LEFT JOIN` + `array_agg` with bcfp's `ORDER BY wscode_ltree, localcode_ltree, downstream_route_measure` (all DESC) for canonical element ordering. `direction` flips the `fwa_downstream` / `fwa_upstream` predicate; `aoi` injects WHERE; `include_equivalents` toggles the bool arg. 20 / 20 PASS in test-frs_network_features.R covering 7 SQL-composition cases. lintr clean.
- Phase 3 done: live bcfp parity test passes 100 % byte-identical on ADMS (1031 / 1031 segments with non-NULL `barriers_pscis_dnstr`; per-segment arrays equal mod sort). Required two refactors during the phase:
  - SQL pattern: LEFT JOIN → subquery-with-INNER-JOIN matching bcfp's exact `load_dnstr` shape (preserves canonical element ordering via the subquery's ORDER BY triple).
  - Test ref query: filter bcfp's wide-per-source `streams_dnstr_barriers` to `barriers_pscis_dnstr IS NOT NULL` for the apples-to-apples PSCIS slice. The unfiltered 15647 was a red herring — most of those rows have non-NULL `barriers_dams_dnstr` but NULL PSCIS.
- 6 / 6 PASS in test-frs_network_features-live.R (1 downstream parity + 1 upstream sanity + the 4 mocked tests already passing).
- Next: Phase 4 — NEWS.md 0.28.0 entry, DESCRIPTION bump, PR.
