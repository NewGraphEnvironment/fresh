# Progress — drop format param

## Session 2026-04-27

- Branch `overlay-species-col` reset to main (was carrying species_col bolt-on; pivoted to drop-format simplification per design discussion)
- PWF baseline written
- Issue #177 updated in place: title + body now reflect "drop format" scope (was "layout decomposition")
- Cross-repo coordination: crate-Claude thread closed today (`link/comms/crate/20260427_fresh_bcfishpass_csv_consumers.md`); decision recorded — link will canonicalize at ingest via forthcoming `lnk_ingest_bcfishpass()`, so fresh sees only canonical shape
- Next: Phase 2 — rewrite `frs_habitat_overlay()`
