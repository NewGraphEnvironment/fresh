# Task: frs_break_find minimum island length filter (issue #118)

## Goal
Separate `distance` (gradient sampling window) from `min_length` (minimum island length). Default `min_length = 0` keeps ALL islands — a 30m waterfall at 20% gradient is a real barrier. The 100m default was silently dropping real barriers.

## Status: in progress

## Phases
- [x] Branch + PWF init
- [x] Add `min_length` param to `frs_break_find()` + `.frs_break_find_attribute()`
- [x] Update SQL: `island_length >= %d` uses `min_len` not `dist`
- [x] Update roxygen docs
- [x] 657 tests pass, ADMS verification: 137 barriers (was 98, +39 recovered)
- [ ] Code-check
- [ ] PR + merge + NEWS + archive
