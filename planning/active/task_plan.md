# Task: Auto-skip thresholds on waterbody_type L/W rules (#131)

## Goal
When a rule has `waterbody_type: L` or `waterbody_type: W`, automatically skip gradient and channel_width threshold inheritance. Lake/wetland flow lines are routing lines — channel width is meaningless.

## Status: in progress

## Phases
- [x] Branch + PWF
- [x] Modify `.frs_rule_to_sql()` — auto-set `inherit_thresholds = FALSE` when `waterbody_type` is L or W
- [x] 4 new tests + 1 existing test updated. 669 pass.
- [ ] Code-check
- [ ] PR + merge + NEWS + archive
