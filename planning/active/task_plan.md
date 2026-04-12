# Task: Preserve multiple labels per break position (#145)

## Goal
Allow multiple labels at the same (BLK, DRM) position in streams_breaks. A gradient_15 and a falls at the same measure should both survive.

## Root cause
frs_network_segment.R line 191-196: DELETE deduplicates on (blue_line_key, downstream_route_measure) only. Drops one label when two break sources share a position.

## Fix
Add `AND a.label = b.label` to only dedup truly identical rows. Different labels at the same position are preserved.

## Phases
- [x] Branch + PWF
- [x] Fix dedup: add `AND a.label = b.label` to only remove exact duplicates
- [x] Integration test: two mock break sources at same position, verify both labels survive
- [x] 692 tests pass
- [ ] Code-check
- [ ] PR + merge + archive
