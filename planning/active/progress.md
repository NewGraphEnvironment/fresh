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
- Next: start Phase 1 — function signature + validation + roxygen + NAMESPACE.
