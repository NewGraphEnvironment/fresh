# Task: Fix gradient barrier precision loss (issue #110)

## Goal

Fix two related precision bugs introduced in v0.11.0 (#101) where distinct gradient thresholds collapse to the same `gradient_N` label, silently losing biological precision.

## Status: in progress

## Why this matters

`as.integer(thr * 100)` rounds 0.05 and 0.0549 both to 5, so:

1. **Dedup drops one**: `!duplicated(...)` keeps only one threshold; the other is silently lost
2. **Labels collide**: Both produce `gradient_5`. A user inspecting the breaks table sees `gradient_5` and assumes 5%, but the actual break could be at 5.49%

Result: species with `spawn_gradient_max = 0.05` and another at `0.0549` would share a single break point. Segments between 5.0% and 5.49% get classified incorrectly.

## Design

### Label format: `gradient_NNNN`

4-digit zero-padded basis-points (threshold × 10000):

| Threshold | Old (lossy) | New |
|-----------|-------------|-----|
| 0.0249 | gradient_2 | gradient_0249 |
| 0.05   | gradient_5 | gradient_0500 |
| 0.0549 | gradient_5 (collision!) | gradient_0549 |
| 0.10   | gradient_10 | gradient_1000 |
| 0.15   | gradient_15 | gradient_1500 |
| 0.25   | gradient_25 | gradient_2500 |

- Format: `sprintf("gradient_%04d", as.integer(round(thr * 10000)))`
- Parse: `as.numeric(m[2]) / 10000`
- Resolution: 0.0001 (1 basis point) — sufficient for any meaningful threshold
- Sorts naturally as strings; parses cleanly as integer

### Backward compat in parser

`.frs_access_label_filter()` accepts both formats:
- New: `^gradient_(\d{4})$` → divide by 10000
- Legacy: `^gradient_(\d{1,3})$` → divide by 100

Write side commits to new format. Read side handles legacy `gradient_15` from user-supplied labels (e.g. `frs_break_find(label = "gradient_15")`).

### Dedup fix

```r
# Old (lossy):
all_thresholds <- all_thresholds[
  !duplicated(as.integer(all_thresholds * 100))]

# New:
all_thresholds <- sort(unique(c(access_thresholds, extra_thresholds)))
```

`unique()` on actual numeric values preserves distinctions.

## Phases

### Phase 1: Branch and core fix

- [ ] Create branch `110-gradient-label-precision`
- [ ] Fix dedup + label format in `R/frs_habitat.R` sequential branch
- [ ] Fix dedup + label format in `R/frs_habitat.R` mirai parallel branch
- [ ] Update `.frs_access_label_filter()` in `R/frs_habitat_classify.R` to accept both formats
- [ ] Verify with `devtools::test()` and code-check

### Phase 2: Update tests

- [ ] `test-frs_habitat_classify.R`: update mock labels to new format
- [ ] `test-frs_habitat_classify.R`: add test verifying legacy `gradient_15` still parses correctly (backward compat)
- [ ] `test-frs_habitat.R`: add test verifying `breaks_gradient = c(0.05, 0.0549)` produces TWO distinct breaks (regression test for #110)
- [ ] Run code-check

### Phase 3: Update docs and examples

- [ ] `R/frs_network_segment.R`: example docstrings
- [ ] `R/frs_habitat_classify.R`: example docstrings, parameter doc text
- [ ] `README.md`: example
- [ ] `devtools::document()` clean

### Phase 4: Verify and release

- [ ] Full test suite passes
- [ ] Integration test on ADMS sub-basin: confirm distinct labels at 0.05 and 0.0549
- [ ] Push branch
- [ ] Create PR with SRED tag
- [ ] Code-check final review
- [ ] Merge with `--admin --delete-branch`
- [ ] Bump DESCRIPTION + NEWS.md (no git tag)

### Phase 5: Archive PWF

- [ ] `mv planning/active planning/archive/2026-04-issue-110-gradient-label-precision`
- [ ] Add README.md outcome summary
- [ ] Recreate empty `planning/active/`
- [ ] Commit "Archive planning files for issue #110"
