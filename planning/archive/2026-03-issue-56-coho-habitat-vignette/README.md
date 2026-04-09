## Outcome

Built the coho habitat pipeline vignette and added `to=` parameter support to `frs_network()` for DB-side persistence. Established the pattern of keeping geometry on PostgreSQL throughout the pipeline rather than pulling to R, which became the foundation for the v0.8.0 unified pipeline (`frs_network_segment` + `frs_habitat_classify`).

## Key Learnings

- DB-side persistence avoids R memory bottleneck at province scale
- `frs_network()` `to=` parameter became the precursor to `frs_network_segment()` orchestrator
- Vignette `.Rmd.orig` pre-knit pattern doesn't work with bookdown cross-refs — use live execution or skip cross-refs
- Bundled test data via `data-raw/` scripts is the right pattern for reproducible vignettes

## Closed By

PR #56 (commit aac96ef) — "Add coho habitat pipeline with DB-side classification"

These files were stale in `planning/active/` from March 2026. Archived in April 2026 during workflow hygiene reset before issue #110 work.

## SRED

Relates to NewGraphEnvironment/sred-2025-2026#16
