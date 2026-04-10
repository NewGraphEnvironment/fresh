# Task: Per-rule threshold overrides in YAML (issue #116)

## Goal

Allow rules to specify `gradient` and `channel_width` overrides that win over CSV inheritance. Currently it's all-or-nothing (`thresholds: true/false`). This enables the bcfishpass pattern where `waterbody_type=R` skips channel_width_min but keeps gradient.

## Status: in progress

## Phases

- [x] Branch + PWF init
- [x] Update `.frs_rule_to_sql()` — rule-level gradient/channel_width overrides CSV inheritance
- [x] Update `.frs_validate_rule()` — accept gradient and channel_width keys, validate as numeric [min, max]
- [x] 5 new tests: gradient override, channel_width override, override with thresholds=false, bad format validation
- [x] Update bundled YAML: all R-polygon rules get `channel_width: [0, 9999]`
- [x] 657 tests pass
- [ ] Code-check
- [ ] PR + merge + NEWS + archive PWF
