# Progress: Issue #118 — min_length filter

### 2026-04-09
- Branch `118-min-length-filter` created
- PWF initialized
- Added `min_length` param (default 0) to `frs_break_find()` and `.frs_break_find_attribute()`
- SQL: `WHERE island_length >= min_len` (was `dist`)
- Updated roxygen docs
- 657 tests pass
- ADMS verification: 137 barriers at 15% (min_length=0) vs 98 (min_length=100) — 39 short barriers recovered
