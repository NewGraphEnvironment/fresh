# Progress — Backlog move 2: rules loading and persist validators (#319)

## Session 2026-11-22

- Plan-mode exploration — phases approved by user
- Created branch `319-backlog-move-2-rules-loading-and-persist` off origin/main (f3e331d); claimed #319 in-flight
- Scaffolded PWF baseline from issue #319 with approved phases
- Next: start Phase 1
- Phase 1 (#267): two C-locale tests, red on the unfixed loader (empty rules; truncation after a mid-file em-dash), green after reading with `yaml.load(readLines(encoding = "UTF-8"))`. test-frs_params.R: 0 fail.
