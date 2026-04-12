# Progress: Issue #131

### 2026-04-11
- Branch `131-skip-thresholds-waterbody` created
- PWF initialized
- Modified `.frs_rule_to_sql()` — auto-skip gradient/cw inheritance when waterbody_type is L or W
- 4 new tests: lake auto-skip, wetland auto-skip, river still inherits, lake with explicit override
- Updated existing CO 4-rule test (lake rule now auto-skips, so 2 not 3 gradient predicates)
- 669 tests pass
