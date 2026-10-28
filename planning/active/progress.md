# Progress — frs_network_features(): every walk probes the segments once per feature in the province (#272)

## Session 2026-10-28

- Plan-mode exploration — phases approved by user, then parked
- Probed the sent SQL, the issue's prefilter and three alternatives on the local Docker fwapg, read-only, with digests (`findings.md`)
- Created branch `272-frs-network-features-every-walk-probes-t` off main
- Scaffolded PWF baseline from issue #272 with approved phases; plan review in `review-plan.md`
- Next: parked 2026-10-28; resume with the command below, then "start Phase 1"

### Resume

```bash
cd /Users/airvine/Projects/repo/fresh && git fetch -q origin && git checkout 272-frs-network-features-every-walk-probes-t && git pull --ff-only && git merge origin/main
```

The approval of 2026-10-28 covered the baseline only. The run-to-PR mandate starts when
the owner says to resume.

## Session 2026-10-28 (resumed)

- Resumed under the run-to-PR mandate; branch current with origin/main, issue body unchanged since planning, CI green
- Phase 1: 26 mocked assertions + one local live test fail on the unchanged function (28 failures, 81 passes); the live equivalence assertions pass, so the reference join agrees with the current SQL
- Phase 2: scoped walk implemented; `devtools::test(filter = "network_features")` 0 fail / 121 pass, including the local VICT comparison (both `include_equivalents`) and the bcfishpass ADMS byte-identity test on the new path. The error on a failed DDL names a missing `segments` column as a second cause, since that fails at the same statement
- Mutation runs: the VICT live test missed both prefilter arms. Moved it to SKGT with NULL-coded feature copies; it now fails on removing either arm (2 and 6 failures) or the `DROP` (3)
- Phase 3: full run SALR LKEL CHWK LSKE (19:40-20:57 UTC), 56 rows, every `d_set` agrees; old SQL censored at 600 s on all 8 CH/BT walks, new 0.3-8.4 s; log README with the table
- Phase 4: research section "Prefiltering the feature side" with the Phase 3 table and the two open items; `research/README.md` row; CLAUDE.md Technical notes bullet
