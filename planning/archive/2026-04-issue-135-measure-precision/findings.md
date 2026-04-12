# Findings: Issue #135

frs_break_apply already rounds to integer (line 597). The real issue: the breaks TABLE used for access gating keeps full precision (2 decimal places from frs_break_find). Parameterize the rounding and apply it consistently to BOTH geometry splitting AND the breaks table.
