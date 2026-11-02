# #282 — custom-AOI persist deletes other watershed groups' rows from `to_streams`

## Outcome

`frs_habitat()` overwrote its partition of `to_streams` by watershed group when
given `wsg` and by `id_segment` otherwise, and `id_segment` does not identify a
row in a shared table, so a custom-AOI run deleted rows it would not put back.
The issue, this plan's first draft, `findings.md` and shipped `NEWS.md` 0.46.0 all
explained it with a mechanism the code does not have — "each working table numbers
its segments independently" describes neither assignment site. Measuring the two
artifacts instead reopened the key decision the plan had already closed: the pair
key `(id_segment, watershed_group_code)` the owner picked at the gate fixes
nothing on a table built by current code, because the residual collisions there
are **same-group**. A third key the plan never considered, the parent segment
`linear_feature_id`, is correct against both table generations and is also the
only one that clears stale sub-segments; it was put back to the owner with the
numbers and chosen. Both drifted persist blocks were then consolidated into one
internal helper, split so the SQL builder is a pure string function that runs on
CI where no database exists. `/code-check branch` ran four rounds and **three of
them found a defect inside the previous round's fix** — a one-shot NULL-key proxy,
a data-modifying CTE that is not atomic, and finally the mutation-sweep site list
itself, which round 3's fix had left unresolvable so the instrument for proving
the guards fire could not run on the tree it shipped with. Round 3 named the
single mechanism behind every finding: **a property of the code standing in for a
property of the database**, each proxy decidable from the source alone, which is
why each one passed self-review and only failed against a real table. The loop
closed on round 4's enumeration and the sweep that measures it, not on a quiet
round.

Durable findings went to [`research/id_segment_identity.md`](../../../research/id_segment_identity.md):
the key that shipped and the three facts that decide it, why the sibling habitat
tables cannot use it (#293), and the two database properties no reading of the
source reveals — the unique index every persisted streams table carries, and that
a data-modifying CTE is not an atomic overwrite.

## Measurement

- **The reopened key decision.** Of one run's 275 derived `id_segment` values, 81
  each equalled a real `linear_feature_id` **in the run's own watershed group**
  and 0 fell in another group — so the pair key neither fixes the defect nor is
  safe to assume unique on a current-code table. 0 `linear_feature_id` spans a
  watershed group province-wide, which is the property that makes the parent
  segment correct. Changed the fix from the key approved at the gate to a third
  key the plan had not considered.
- **The loss cannot have happened on the table that exists.** `fresh.streams`
  holds 3,802,814 rows across 98 groups numbered 1..n per group, with **0** rows
  where `id_segment = linear_feature_id`; a current-code job's ids cannot collide
  with those at all. This reframed the audit from "find the damage" to "say which
  table generation each number is about", which is why
  `data-raw/audit_persist_282.R` reports two reference sets.
- **Float equality on `downstream_route_measure` is exact** — 275 of 275 derived
  measures integral, base measures copied `double precision` to `double
  precision`, 464 of 464 `(lfid, drm)` pairs reproduced across two runs of one
  AOI. Recorded because it was asked; it decides nothing, since the key chosen
  never names a measure.
- **296 `streams` relations carry a unique index; 0 do not** (198 on `id_segment`
  alone, 98 on the pair). `CREATE TABLE ... LIMIT 0` copies no constraints, so
  every fixture — including my own scratch verification of the CTE — could not
  reach the failure mode. Fixtures gained explicit indexes, and restoring the CTE
  in a copy reddens five tests.
- **The data-modifying CTE was wrong where it mattered most.** On a keyed target:
  CTE run 1 OK, run 2 duplicate-key violation, under **both** candidate keys; the
  two-statement form in one transaction OK twice. This was a defect inside round
  1's own atomicity fix.
- **The NULL-key guard was a one-shot proxy.** Reproduced: run 1 ERROR, run 2 OK,
  run 3 OK with the stale NULL row surviving, because `.frs_persist_columns()`
  runs its `ALTER` before the guard raises. Now a property measured every call —
  `count(*) WHERE <key> IS NULL`, 1.43 s on 3.8M rows.
- **Mutation sweep on the final shape: 16 sites, 0 with no test catching them.**
  Baseline 0 red / 0 skip; credited only on red → green → red. The earlier "0 of
  10" is void — measured against `f1f649b`, before six of the rows existed and
  before round 4 found the committed list unresolvable.
- **Closing runs:** full suite FAIL 0 | WARN 21 | SKIP 6 | PASS 2542 (up from
  2501 pre-review; warnings and skips are `main`'s). `workers = 2L` through the
  mirai path PASS, 6/6. `lintr::lint_package()` 1471 against `origin/main`'s 1400
  in a worktree: +70 `indentation_linter`, a class the package carries 1400 of
  before the branch, plus one `brace_linter` that was mine and is fixed.
- **Three siblings filed rather than fixed here:** #293 (the larger loss, whole
  watershed groups from the habitat and `near_river` tables, and not the same
  mechanism), #294 (`to_barriers` keyed on `blue_line_key` alone, 259 blue lines
  spanning groups, which reaches the `wsg` path too), #295 (how a released
  changelog entry carrying the wrong mechanism should be corrected).

## Evidence

- `dev/mutation_sweep_sites_persist_282.csv` — the 16 committed sweep sites; run
  with `dev/mutation_sweep.R` and the filter `'^(frs_habitat|utils)$'`.
- `data-raw/audit_persist_282.R` — the per-group shortfall audit, both reference
  sets, re-runnable against any persisted `to_streams`.
- `findings.md` here — every query, with the number it returned and when.
- `review-plan.md` and `review-round1.md` … `review-round4.md` here — the plan
  review and the four `/code-check branch` rounds, each with my verdict beside
  the reviewer's finding.

Closed by: PR to follow on branch `282-custom-aoi-persist-deletes-other-watersh`
