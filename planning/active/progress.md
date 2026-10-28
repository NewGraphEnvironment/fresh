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
- Validation: full `devtools::test()` 0 failed / 0 error / 6 skipped / 2038 passed (20:59-21:00 UTC); network_features files 130 passed, 0 skipped (bcfishpass ADMS and local SKGT both ran); lintr clean on touched files after qualifying `testthat::local_mocked_bindings` in the mock helper; `devtools::document()` no change; `pkgdown::check_pkgdown()` no problems
- `/code-check branch`: 4 rounds (`review-round1.md` to `review-round4.md`). No bug in R code in any round; fixes were to stated claims: SKGT's one Fraser-coded segment, skipped runs logged as timeouts, a 22-pair count's population, the unscoped plan, the pooling failure points (round 4 found round 3's pooling fix half right), `fwa_upstream()`'s criteria, the run window. Ended by enumeration: the scoped call's 7 statements against the 3 named conditions (`findings.md`), on top of round 3's 58-claim table that round 4 re-checked
