# Task: to_barriers parameter (#143)

## Goal
Persist the gradient barriers table when `to_barriers` is provided. Currently dropped after segmentation.

## Phases
- [x] Branch + PWF
- [x] `to_barriers` param — persist grad_tbl with ltree enrichment before cleanup
- [x] Both sequential + mirai branches
- [x] 2 integration tests (persist + NULL), 690 total pass
- [ ] Code-check
- [ ] PR + merge + archive
