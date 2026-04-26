# PR #175 — overlay rename + bridge (v0.21.0)

**Closed:** 2026-04-26
**Tag:** v0.21.0
**Result:** Pre-1.0 cleanup. `frs_habitat_overlay()` params renamed (`table`/`known` → `to`/`from`). New `bridge = NULL` for 3-way range-containment joins, lets `id_segment`-keyed targets overlay from `(blk, drm)` range sources. Drop `known` shortcut on `frs_habitat_classify`. 816 PASS full suite, 54 scoped.

## Outcome
Function now reads as a sentence: `frs_habitat_overlay(from = X, to = Y, bridge = Z)`. Domain-agnostic.

## Closing artefacts
- PR: https://github.com/NewGraphEnvironment/fresh/pull/175
- Tag: v0.21.0
- Documented limitation: range column names hardcoded to FWA convention. Follow-up if non-FWA schemas need it.
