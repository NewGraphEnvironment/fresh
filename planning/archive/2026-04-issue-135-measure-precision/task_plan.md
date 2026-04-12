# Task: measure_precision parameter (#135)

## Goal
Parameterize the measure rounding in `frs_break_apply()` and propagate through `frs_network_segment()`. Currently hardcoded to integer (`round(...)::integer`). Default 0 (integer, matching bcfishpass). Higher values = more decimal places.

## Status: in progress

## Key finding
`frs_break_apply()` line 597 ALREADY rounds to integers. The issue is about making this configurable and also rounding the BREAKS TABLE measures to match (for consistent access gating).

## Phases
- [x] Branch + PWF
- [x] `frs_break_apply()` — parameterize rounding with `measure_precision` (default 0)
- [x] `frs_network_segment()` — round breaks table + dedup before splitting, pass measure_precision to break_apply
- [x] `frs_habitat()` — pass through (sequential + mirai + .run_job)
- [x] 675 tests pass
- [ ] Code-check
- [ ] PR + merge + NEWS + archive
