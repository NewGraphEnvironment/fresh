# Progress — Fetchers: fix row order, and add simplify and a polygon extent, so map layers rebuild identically (#286)

## Session 2026-10-31

- Plan-mode exploration — phases approved by user
- Created branch `286-fetchers-fix-row-order-and-add-simplify` off origin/main
- Scaffolded PWF baseline from issue #286 with approved phases
- Next: start Phase 1
- Phase 1: `.frs_geom_select()`, `.frs_validate_simplify_m()`, `.frs_order_by()` added; `.frs_build_where()` takes `aoi`/`conn`. Helper tests in test-utils.R (83 pass). Fetcher-level mocked tests land with Phase 2 so each commit is green.
- Phase 2: three fetchers take `aoi`, `simplify_m`, `order_by`; lake/wetland now validate `table`/`cols` like streams. `aoi` sits after `bbox`; every caller found in local checkouts (breaks, fresh tests) passes arguments by name. New `test-frs_fetch_sql.R` (mocked) failed before the wiring, passes after; fetch filter 49 pass.
- Phase 3: `frs_watershed_at_measure(simplify_m)`; NULL path unchanged (pinned by a mocked test), simplified subbasin is one query (difference + intersects flag). Live: Byman–Ailport subbasin simplified at 50 m is a POLYGON, identical() on repeat, 3.8 s.
- Plan review (Plan agent, review-286.md) arrived; 2 blockers + 4 gaps verified and folded in (findings.md "Plan review verdicts"). Line churn check run early: streams byte-identical locally and across GEOS 3.9 vs 3.10 (52,291 segments, two tolerances); lakes differ 1–2 vertices in 46/1,754 across GEOS.
- utils|fetch|watershed_at_measure: 191 pass.
- Phase 4: `test-frs_fetch_live.R` (19 pass): identical() + strictly sorted keys for simplified lakes/wetlands/streams; `limit` = lowest keys; stored `area_ha` kept and stream start points unchanged under simplify; aoi excludes a lake whose envelope (bbox) a 1 m corner square hits; simplified subbasin identical on repeat, area within 1% of raw. identical() on two st_read results is fair: TRUE on repeat, and sf carries no per-read pointer attributes.
- Guards proved by mutation in a scratch copy (failing tests per planted defect): no ORDER BY 8, Normalize on streams 3, no digits = 15 1, no empty-drop 1, aoi not appended 5, subbasin difference unsimplified 1.
- Phase 5: lint of changed files: no new lints of mine (remaining are pre-existing indentation, and object_usage from the stale installed package not knowing the new helpers). `pkgdown::check_pkgdown()` clean. NEWS is written at release by `/gh-pr-merge` (0.48.0's came in the Release commit), so the `limit` behaviour change goes in the PR body.
