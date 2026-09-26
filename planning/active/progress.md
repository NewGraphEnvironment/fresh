# Progress — Phase 2: enrich streams with mad_m3s and add mad predicate to rule evaluator (#114)

## Session 2026-09-25

- Plan-mode exploration — phases approved by user (Option B: rules-explicit MAD only)
- Created branch `114-phase-2-enrich-streams-with-mad-m3s-and` off main
- Scaffolded PWF baseline from issue #114 with approved phases
- Next: start Phase 1
- Phase 1: tests written; they fail as expected. `.frs_rule_to_sql` tests went into `test-frs_params.R` (where the existing evaluator tests live), not `test-utils.R`. DB segment test went into `test-frs_habitat.R` next to the #145 segment test.
- Pre-existing failure on main: `test-frs_params.R:92` expects 4 CO rear rules but the bundled YAML has 5. Out of scope — flag in the PR.
- Phases 2+3 implemented. Committed together because `R/utils.R` carries both the persist helper and the evaluator change.
- Code-check ran 3 rounds.
  - Round 1 found a real bug: the positional `to_streams` INSERT broke on tables persisted by older runs, after the DELETE had already run. Also `mad` accepted Inf.
  - Round 2 was clean. One note, fixed: `[true, 5]` was being coerced.
  - Round 3 found an empty `mad:` silently skipped, and a defect inside round 1's fix (types not compared).
  - The loop ended on an enumeration (see findings.md).
- Spot-check on ADMS, local fwapg: CO spawn with the cw rule = 861 segments; with `mad: [0.164, 9999]` added = 597, a strict subset.
- BULK/LDEN have no rows in `fwa_stream_networks_discharge`. Coverage is 150 WSGs, 123 with MAD. Noted in #220.
- Full suite on local fwapg: 1055 pass, 6 fail. All 6 are environmental (3 need the tunnel, 2 need the bcfishpass schema) or pre-existing (`test-frs_params.R:92`).
- Filed follow-up #220 (per-WSG cw/mad model switch).
