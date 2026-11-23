# Progress — Backlog move 2: rules loading and persist validators (#319)

## Session 2026-11-22

- Plan-mode exploration — phases approved by user
- Created branch `319-backlog-move-2-rules-loading-and-persist` off origin/main (f3e331d); claimed #319 in-flight
- Scaffolded PWF baseline from issue #319 with approved phases
- Next: start Phase 1
- Phase 1 (#267): two C-locale tests, red on the unfixed loader (empty rules; truncation after a mid-file em-dash), green after reading with `yaml.load(readLines(encoding = "UTF-8"))`. test-frs_params.R: 0 fail.
- Phase 2 (#222 rules): `.frs_validate_rule_range()` shared by mad/gradient/channel_width (finite, min <= max, per-element); generic "has no value for" check on every other key; loader stores the three ranges as numeric. Bad-gradient test message updated. params/utils/near_river/predicates test files: 0 fail.
