# Progress — Rule condition: a river of at least Q m³/s within D m downstream (#259)

## Session 2026-10-21

- Plan-mode exploration (two Explore agents on the rule grammar and the network primitives, one Plan agent on the design; probes on BULK) — phases approved by user as parked
- Created branch `259-rule-condition-a-river-of-at-least-q-m-s` off main
- Scaffolded PWF baseline from issue #259 with approved phases; Plan review folded in (`review-plan.md`): commits `0b8a035`, `988bcef` (the BULK probe SQL)
- Next: parked 2026-10-21; resume with the command below, then "start Phase 1"

### Resume

```bash
cd ~/Projects/repo/fresh && git fetch -q origin && git checkout 259-rule-condition-a-river-of-at-least-q-m-s && git pull --ff-only && git merge origin/main
```

## Session 2026-10-20 (resume)

- Open items answered with the recommended options: (a) decision 7, (b) document and pin.
- Phase 1: grammar, compiler, predicates threading, spec collector. `test-near_river_rules.R` 63 pass; `test-frs_params.R` 178, `test-frs_habitat_predicates.R` 111, `test-utils.R` 59 unchanged. Mutants: allowlist removal 4 failures, OR grouping removed 7.
- Phase 2: `frs_near_river()` + `helper-near_river.R` fixture. 24 pass; mutants red (bank 9, origin filter 7). Plan corrections: origins below max Q, Lmax per (waterbody_key, blue_line_key).
- Phase 3: classify builds `<to>_near_river` before the species loop and threads it to both models' predicates; integration test 5 pass; `frs_habitat()` unchanged. Parallel workers load the installed package (`library(fresh)`), so a dev check needs the branch in a scratch library via `R_LIBS`.
