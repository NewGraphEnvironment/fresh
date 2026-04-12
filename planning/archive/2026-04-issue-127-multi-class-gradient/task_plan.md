# Task: Multi-class gradient barrier detection (issue #127)

## Goal
Replace boolean above/below gradient detection with bcfishpass's multi-class approach. One pass tags every vertex with its gradient class (5,7,10,12,15,20,25,30), groups consecutive same-class vertices into islands, places one barrier at each class transition.

## Status: in progress

## Phases
- [x] Branch + PWF
- [x] New `.frs_break_find_multiclass()` — multi-class CASE, lag by grade_class, group per class, gradient_class output, blk_filter, parameterized classes
- [x] Updated `frs_break_find()` — new `classes` + `blk_filter` params, dispatches to multiclass when classes provided
- [x] Updated `frs_habitat()` — single `frs_break_find(classes=)` call replaces per-threshold loop, label column added via SQL UPDATE
- [x] Updated mirai parallel branch — same changes
- [x] 658 tests pass
- [ ] Code-check
- [ ] Integration test on ADMS
- [ ] PR + merge + NEWS + archive
