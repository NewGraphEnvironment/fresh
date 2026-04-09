# Progress: Issue #110 — Gradient barrier precision loss

## Session log

### 2026-04-09

- Issue #110 filed by user (precision-loss bugs in v0.11.0 from #101 implementation)
- Workflow audit: planning/active/ had stale files from PR #56 (March)
- Archived PR #56 planning files to `planning/archive/2026-03-issue-56-coho-habitat-vignette/` with outcome README
- Created fresh `planning/active/{task_plan,findings,progress}.md` for #110
- Initial commit: `ee5da61 Archive stale planning files for issue #56 (coho habitat vignette)`

#### Phase 1: Branch and core fix ✓
- Branch `110-gradient-label-precision` created
- Replaced lossy dedup with `unique()` in both sequential and mirai branches
- New `gradient_NNNN` label format via `.frs_gradient_label()` helper
- Updated `.frs_access_label_filter()` to accept both new + legacy formats

#### Phase 2: Update tests ✓
- Updated mocks in test-frs_habitat_classify.R to new format
- Added 9 label parser tests: legacy compat, mixed format, malformed, parametric
- Added 6 validation tests for `.frs_validate_gradient_thresholds()`
- Added regression test for 0.05 vs 0.0549 distinct labels

#### Phase 3: Update docs and examples ✓
- Updated examples in frs_network_segment.R, frs_habitat_classify.R, README.md
- Documented both formats in label_block parameter doc

#### Phase 4: Verify and release
- All 600 tests pass
- Commit: `ad94bc7 Fix gradient barrier precision loss with new label format`
- Code-check round 1: found latent bug — auto-derived thresholds bypass validation when user passes custom params. Could cause silent label collision in the auto-derive path.
- Fix commit: `6acfa94 Validate combined gradient thresholds in frs_habitat()`
- Code-check round 2: clean
- (next: push, PR, merge)

#### Phase 5: Archive PWF
- (pending after merge)
