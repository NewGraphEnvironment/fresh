# Findings: Issue #131

Lake/wetland flow lines are routing lines through waterbodies — gradient and channel_width are meaningless. The fix: in `.frs_rule_to_sql()`, when `waterbody_type` is L or W, force `inherit_thresholds = FALSE` for gradient and channel_width (but NOT for the rule's own explicit overrides via `rule[["gradient"]]` or `rule[["channel_width"]]`).

Actually simpler: just skip gradient/cw inheritance when waterbody_type is L or W. Rule-level explicit overrides still apply if someone sets them. The `thresholds: false` workaround becomes unnecessary for lake/wetland rules.
