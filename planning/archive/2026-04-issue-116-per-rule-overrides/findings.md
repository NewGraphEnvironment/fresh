# Findings: Issue #116

Small change. `.frs_rule_to_sql()` currently has all-or-nothing CSV threshold inheritance. Need per-field override: if a rule specifies `gradient` or `channel_width`, use the rule value; else inherit from CSV when `thresholds: true`.

The `gradient` and `channel_width` keys need to be added to `valid_predicates` in `.frs_validate_rule()`. Validate as numeric vectors of length 2 (min, max).
