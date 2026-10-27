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
