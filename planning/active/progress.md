# Progress — Fetchers: fix row order, and add simplify and a polygon extent, so map layers rebuild identically (#286)

## Session 2026-10-31

- Plan-mode exploration — phases approved by user
- Created branch `286-fetchers-fix-row-order-and-add-simplify` off origin/main
- Scaffolded PWF baseline from issue #286 with approved phases
- Next: start Phase 1
- Phase 1: `.frs_geom_select()`, `.frs_validate_simplify_m()`, `.frs_order_by()` added; `.frs_build_where()` takes `aoi`/`conn`. Helper tests in test-utils.R (83 pass). Fetcher-level mocked tests land with Phase 2 so each commit is green.
