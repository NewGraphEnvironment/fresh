# PR #170 — frs_habitat_known()

**Closed:** 2026-04-25
**Tag:** v0.18.0
**Result:** New exported `frs_habitat_known()` ships. ORs known-habitat boolean flags from a wide-format lookup table INTO an existing `streams_habitat`. Purely additive (FALSE → TRUE only). Idempotent. 11 mocked unit tests + 3 integration tests; 749 PASS / 0 FAIL on full suite.

## Outcome
Fresh-side mechanism for blending model output with manually-curated knowns lands clean. link's `lnk_pipeline_classify` can now call this helper as a post-step to close link#55.

## Closing artefacts
- Merge: 48325dc (or whatever main HEAD is post-merge)
- PR: https://github.com/NewGraphEnvironment/fresh/pull/170
- Tag: v0.18.0
