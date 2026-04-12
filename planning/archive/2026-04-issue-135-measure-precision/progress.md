# Progress: Issue #135

### 2026-04-12
- Branch created, PWF initialized
- Found that frs_break_apply already rounds to integer (line 597)
- The issue is about parameterizing the rounding + rounding the breaks table to match
- Parameterized rounding in frs_break_apply, frs_network_segment, frs_habitat
- Breaks table rounded + deduped before enrichment and splitting
- 675 tests pass
