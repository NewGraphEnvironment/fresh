# Progress — frs_point_snap(): fwapg's tie rule, and a sweep and live tests for the reworked fwapg functions (#266)

## Session 2026-10-27

- Plan-mode exploration: fwapg's migration read verbatim, both candidate databases probed, call
  costs and input sizes measured, the KNN plan checked under the new tie key, wet#127's
  implementation read in full. Phases approved by user at the gate.
- Gate decisions: the trial helper exported from fresh (named `frs_migration_trial()`); sweep on m4's local docker fwapg; both
  pending migrations tried in filename order; link#383 after merge.
- Created branch `266-frs-point-snap-fwapg-s-tie-rule-and-a-sw` off main (db65bdd)
- Scaffolded PWF baseline from issue #266 with the approved phases
- Plan-agent review before the baseline commit (`planning/active/review-plan.md`): 6 blockers,
  5 gaps, 3 ordering problems. Two Phase 4 pins were not provable as written
  (`fwa_watershedatmeasure` has no top bound to close; `frs_cluster()`'s trace starts are segment
  lower bounds), the before-run drift guard was unachievable, and the gated helper had no
  connection of its own. All folded into `task_plan.md`, with three items the agent could not run
  verified at the database afterwards.
- Next: start Phase 1

## Session 2026-10-27 (continued)

- **Phase 1 done** — `frs_migration_trial()` + `.frs_migration_trial_sql()` + `.frs_sql_blank()`
  + `.frs_sql_scan()`, `withr` promoted to `Imports`, `frs_fwapg_conn()` / `local_fwapg()` added
  to `tests/testthat/helper-db.R` (moved forward from Phase 4, which needed it first). 84 tests,
  including a live test that applies both real fwapg migrations and asserts the rollback.
  Verified end to end: both apply in 0.1 s, `include_disconnected` appears, `exbc` goes, both
  revert on the frame's exit.
- **Phase 2 done** — the tie rule at all three ordering sites, on the raw measure carried out of
  the lateral as `measure_raw`. Six tests red on `main`, green after. `EXPLAIN` confirms the KNN
  index-ordered scan survives. Gauge points re-measured (see `findings.md`): 08KD006 is the only
  one of the three that pins anything.
- **Phase 3** — `data-raw/point_snap_tie_sweep.R` written and smoke-run end to end over all three
  states. Batched `fwa_locatealong` measured at 0.3 ms/call (not 70 ms), so the exhaustive run is
  affordable. Full run pending.
- **Code check** — round 1: 5 findings, all fixed (the biggest: the ported PCRE grammar refused a
  plpgsql `END;`, which fwapg's own `db/schema.sql` writes seven times, so the screen was replaced
  with a SQL lexer). Round 2: 7 findings, all fixed (the biggest: the lexer had no `"..."` token
  class, so a `--` or `'` inside a quoted identifier blanked real SQL and let a top-level `COMMIT`
  through — a fail-open). Fixing those surfaced two more inside the fixes, so round 3 was asked to
  name the mechanism and enumerate rather than hunt instances.
- Next: round 3, commit phases 1-3, then the full sweep, Phase 4 and Phase 5.
