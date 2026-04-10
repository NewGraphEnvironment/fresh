# Progress: Issue #116 — Per-rule threshold overrides

### 2026-04-09
- Branch `116-per-rule-threshold-overrides` created
- PWF initialized
- `.frs_rule_to_sql()`: rule-level gradient/channel_width checked BEFORE CSV inheritance. If rule has the field, use it; else inherit from CSV when thresholds: true
- `.frs_validate_rule()`: accept gradient and channel_width keys, validate as numeric vector of length 2 [min, max]
- Bundled YAML: all `waterbody_type: R` rules now have `channel_width: [0, 9999]` (skip cw_min on river polygons, matching bcfishpass pattern)
- 5 new tests: gradient override, cw override, override + thresholds=false, bad format
- 657 tests pass
