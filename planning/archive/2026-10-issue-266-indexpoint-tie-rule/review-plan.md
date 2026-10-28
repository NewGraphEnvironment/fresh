# Plan review — #266, before the baseline commit

Plan agent read `task_plan.md` against the issue, the code, wet's branch and the two fwapg
migration bodies. 6 blockers, 5 gaps, 3 ordering problems, 5 assumptions, 2 acceptance problems.
Everything below is folded into `task_plan.md`; this file is the record of why.

The three items the agent could not check (its `psql` was blocked) were verified here afterwards —
see "Verified at the DB" at the end.

## Blockers

| # | finding | resolution in the plan |
|---|---|---|
| B1 | Phase 4 pinned "a tied position that `frs_watershed_at_measure()` now places". Neither migration touches `fwa_watershedatmeasure`, and its segment pick (`downstream_route_measure <= v_measure ORDER BY desc LIMIT 1`, drop_exbc body lines 36-39, 68-71, 342-345) has **no top bound**, so there is no open top to close. After Phase 2 the tied measure is `CEIL(m) >= ds_upper`, strictly inside the upper segment, and resolves before the migration too. | Pin replaced. `fwa_watershedatmeasure` calls `FWA_SliceWatershedAtPoint` on rivers (verified in the installed body and at drop_exbc lines 267, 707) and that function is rewritten by the tiebreak migration to clamp its slice fraction — so the provable pin is an **error→success** transition on `line_interpolate_point: 2nd arg isn't within [0,1]`, not a placement. The `exbc` area change becomes a second, separately attributed pin. |
| B2 | Phase 4's `frs_cluster()` pin is not provable: the trace start is always a segment's own `downstream_route_measure` (`R/frs_cluster.R:283-302, 330-333`), inside `[ds, us)` under either rule; and the `CROSS JOIN LATERAL` drops a zero-row trace silently, so "no longer errors" is not a predicate this path can exhibit. | Pin dropped. `frs_cluster()` stays in the sweep as a counted input, with the finding recorded in the research note. |
| B3 | "the before run must reproduce the package's stored output" is unachievable: `research/fwa_point_snap.md`'s parity numbers are a fresh-vs-**link** comparison (`data-raw/point_snap_parity_check.R:34-37` hard-stops without link, which is in neither `Imports` nor `Suggests`), Phase 2 invalidates those tie rows by design, and `inst/extdata/crossings.csv` is 533,291 bcfishpass rows with fractional measures — a sweep input, not stored fresh output. | Guard replaced with database-state population checks that are independent of fresh's tie rule, plus an md5 of the before side's own sorted output written into the log so this run and any later one are comparable. |
| B4 | Sweep scope cannot run in one sitting: `fwa_locatealong` on all of `crossings.csv` is ~10.4 h **per side** at 70 ms a call; PSCIS × `num_features = 5` ≈ 99,525 positions another ~1.9 h per side; "a sample sized to the measured call costs" is not a number. | Locatealong batched one set-returning query per chunk with `LEFT JOIN LATERAL … ON TRUE` (a plain `CROSS JOIN LATERAL` makes a miss vanish — the one number the sweep exists to produce). Savepoint per chunk, row-by-row re-run on a chunk error. Sample sizes written in as numbers with a reproducible rule. |
| B5 | Phase 4's helper had no connector, so it would reach `frs_db_conn()` → the shared m1 instance, against gate decision 2. `helper-db.R` holds only `skip_if_no_schema()` and `skip_if_no_conn()`; neither returns a connection. | Phase 4 adds a `FRESH_PG*` connector with localhost defaults, ported from wet's `helper-fwapg.R`. CLAUDE.md's "Testing on alternate hosts" section is **amended**, not added. |
| B6 | fresh's house style is a **bare** `on.exit(DBI::dbDisconnect(conn))` (`test-frs_point_snap.R:357`, `test-frs_point_locate.R:4`, and others). A bare `on.exit()` replaces the whole handler list, so it silently discards the `withr::defer()` that **is** the rollback. | Gated tests use `add = TRUE` everywhere, and the helper owns the disconnect so test bodies need no `on.exit` at all. |

## Gaps

- **G1** "a runnable `@examples` in the house style for DB-dependent exports" describes a style that
  does not exist: `grep -rn examplesIf R/` is empty and all 39 DB-dependent exports use
  `\dontrun{}` (`R/frs_point_locate.R:16-22`, `R/frs_point_snap.R:85-108`). R-CMD-check runs
  examples on every PR, and this one would need a database *and* a pending migration file on disk.
  → `\dontrun{}`. No `_pkgdown.yml` obligation (three lines, no `reference:` section, so pkgdown
  auto-indexes). Naming: `frs_pg_trial` does not fit `CLAUDE.md`'s `frs_noun_verb` →
  **`frs_migration_trial()`**.
- **G2** `withr` is in `Suggests` (`DESCRIPTION:45`). wet could leave it there because its helper is
  internal; fresh is exporting this and link will call it from an installed package (link also has
  `withr` in `Suggests` only). → promote `withr` to fresh's `Imports`.
- **G3** The "only two assertions encode the old rule" claim is **correct** (the agent grepped for
  the old ORDER BY strings, `candidate_rank`, and any asserted `linear_feature_id`; no `_snaps`
  directory exists). Two dependents were unlisted: `test-frs_point_snap.R:464-470`
  (`candidate_rank == seq_len(nrow(d))`, which holds only while the window order and the final
  order stay identical), and five live files that consume the snap's pick at the same Bulkley
  points — `test-frs_network_downstream.R:37`, `test-frs_network_prune.R:35,54`,
  `test-frs_network_upstream.R:54`, `test-frs_point_locate.R:7`, `test-frs_break.R:258`.
- **G4** A third doc site carries the old rule: `CLAUDE.md:213`, under "Point snap".
- **G5** Two more passages in `research/fwa_point_snap.md` measure the old rule (the "22 equidistant
  ties" parity bullet and the closing "resolves 1 m apart depending on which segment wins the
  tie"). link is not installed, so they cannot be re-run → stamp them as measured against fresh
  0.40.0's lowest-id rule and link 0.50.0.

## Ordering

- **O1** 07FA007 is a **head** case, not a tie, so it cannot be red before the Phase 2 change → it
  moves to Phase 4. And Phase 4 must not depend on the sweep finding a head case (it needs a point
  beyond a head whose `upstream_route_measure` is an exact integer, within tolerance — possibly
  zero of them): construct it by query instead, which is red/green by construction.
- **O2** The three expected ids were measured through `fwa_indexpoint()`, which returns one
  candidate per `blue_line_key`; fresh returns candidates **per segment** and applies its own
  guards. They must be re-measured through `.frs_point_snap_sql()` on `main`'s SQL and on the new
  SQL before being written as assertions, and 07EA001 needs `num_features > 1` or a `col_blk` hint
  for its stream's tie to surface at all.
- **O3** "attribute each change to one of the two migrations" is not measurable from one combined
  trial → three sweep states (base, tiebreak only, both). The two surviving Phase 4 pins belong to
  *different* migrations, so this is not cosmetic.

## Assumptions and acceptance

- **A1** `immediate = TRUE` on `dbExecute()` is load-bearing (RPostgres prepares otherwise, and a
  prepared statement cannot carry multiple commands; these bodies are 1,369 and 895 lines with
  `$$`/`$function$` quoting). The per-file xid check is sound across files: equal, NULL/NA and
  different all refuse. The trial's connection must not already be in a transaction.
- **A2** `DROP FUNCTION` at tiebreak lines 54-55 has no `IF EXISTS`, and only the
  `whse_basemapping` signature had been verified → checked, see below.
- **A3** Verified by the agent: neither migration body matches the refusal grammar's
  non-undoable-call list, and in each the only statement-leading transaction control is its own
  first-line `BEGIN;` and last-line `COMMIT;` — exactly the pair the port blanks.
- **A4** Decision 2 is right but its *reason* was wrong: `DROP FUNCTION` takes
  `AccessExclusiveLock` on the function object, which a plain `SELECT fwa_indexpoint(…)` from
  another session does not acquire. The real reasons are that a `COMMIT` slipping through would
  migrate the shared database for everyone, and `dblink` is installed on m1 so a rollback there is
  not a full undo. Corrected in `task_plan.md` before it reaches the research note.
- **A5** Nothing else contends for m4's `localhost:5432` — except `scripts/habitat/habitat_province.R:15`
  and `habitat_benchmark_island.R:13`, which hardcode it. Don't run those during a sweep.
- **AC1** "deterministic sample" and "byte-identical second run" need a stated rule
  (`ORDER BY md5(<id>::text) LIMIT n`) and a split between a non-reproducible report header and a
  reproducible body. Also: `on.exit()` does not fire at a script's top level under `Rscript`
  (`data-raw/point_snap_parity_check.R:46-49`), and neither does a top-level
  `withr::defer(…, envir = globalenv())` — the rollback must fire on a function's **return**.
- **AC2** The `FRESH_FWAPG_CURRENT=true` gate is sound provided the `skip()` guard precedes the
  connect and no skip helper is involved. Two additions: `'…'::regproc` **throws** when the
  function is absent or ambiguous, so wrap it in `tryCatch` on the skip path (an error there would
  be a test error, not a skip) while leaving it to fail in the gate test; and keep the gate test
  away from any test that sets trial state on a shared connection.

## Verified as correct by the review (not to be re-litigated)

Three ordering sites and their line numbers; that ordering must use the **raw** measure, not the
clamped one, because equal clamped values at a whole-metre vertex would fall through to
`linear_feature_id` and reinstate the old rule; that carrying the raw measure out under an internal
alias leaks no column (`SELECT p.id, s.*` into `c`, explicit outer select list at `:449-461`, and
`ORDER BY` on a non-selected column is legal) — with the caution that the alias must differ from
`col_ds` itself or `s.*` yields two columns of that name.

## Verified at the DB afterwards (m4 localhost:5432, the three the agent could not run)

- `postgisftw.fwa_indexpoint(double precision, double precision, integer, double precision, integer)`
  **exists**, so the un-guarded `DROP FUNCTION` at tiebreak line 54 succeeds. A2 closed.
- Pre-migration `fwa_locatealong` is `plpgsql`, `provolatile = i`, `proparallel = s`,
  `proisstrict = t` — the same markers the migration's version declares
  (`LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE`), so the two sides' batched timings are
  comparable. B4's caveat closed.
- `whse_basemapping.fwa_watershedatmeasure`'s installed body calls **both**
  `fwa_slicewatershedatpoint` and `fwa_upstreambordercrossings`, which is what makes B1's
  replacement pin real: the tiebreak migration rewrites both.
- Re-measuring the three gauge points through fresh's own snap (O2) is Phase 2 work, not a
  pre-baseline check.
