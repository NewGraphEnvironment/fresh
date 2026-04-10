# Task: gradient_recompute parameter (issue #124)

## Goal
Add `gradient_recompute` parameter to `frs_network_segment()`. Default TRUE (current behavior). FALSE = inherit parent gradient, only recompute measures + length.

## Phases
- [x] Branch + PWF
- [x] `frs_col_generate()` gains `exclude` param — skip named columns
- [x] `frs_network_segment()` gains `gradient_recompute` — passes `exclude = "gradient"` when FALSE
- [x] `frs_habitat()` gains `gradient_recompute` — passes through to both sequential and mirai branches
- [x] 657 tests pass
- [ ] Code-check
- [ ] PR + merge + NEWS + archive
