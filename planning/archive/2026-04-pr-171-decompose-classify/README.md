# PR #171 — Decompose habitat classify

**Closed:** 2026-04-25
**Tag:** v0.19.0
**Result:** Pre-1.0 structural refactor. `frs_habitat_predicates()` extracted (pure-R, 42 unit tests). `frs_habitat_known()` renamed to `frs_habitat_overlay()`. `frs_habitat_classify()` shrunk 551→447 lines and gained a `known = NULL` parameter that orchestrates `frs_habitat_overlay()` as a post-step. Refactor invariant verified — SQL emission byte-identical pre/post via /code-check + 786 PASS / 0 FAIL full suite.

## Outcome
Predicate emission is now pure-R testable without DB. classify is a thinner orchestrator. overlay is named for the mechanism not the provenance assumption. Single-call rule-based + observation-overlay classification via `known = NULL` arg.

## Closing artefacts
- PR: https://github.com/NewGraphEnvironment/fresh/pull/171
- Tag: v0.19.0
- Follow-up: frs_habitat_access extraction (Phase 4 of plan, deferred)
