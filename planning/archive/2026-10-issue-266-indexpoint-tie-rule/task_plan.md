# Task: frs_point_snap(): fwapg's tie rule, and a sweep and live tests for the reworked fwapg functions (#266)

## Context

`frs_point_snap()` breaks an exact distance tie on the **lowest `linear_feature_id`**. A tie is a
point whose nearest point on two adjacent segments of one stream is the vertex they share — common
(any point in the wedge outside a bend), and in about half of them the two segments' localcodes
differ because a tributary joins at that vertex.

fwapg is moving to a positional rule. The migration under review (NewGraphEnvironment/fwapg#41,
PR #43, upstream smnorris/fwapg#201) writes it as, verbatim from
`db/migrations/202610240132__indexpoint_tiebreak.sql`:

```sql
ORDER BY blue_line_key, distance_to_stream, downstream_route_measure DESC, linear_feature_id
```

the segment **starting** at the vertex — the one a measure there falls on, since measures resolve
`[downstream, upstream)`. Lowest id has nothing to do with position, so after the migration fresh
and `fwa_indexpoint()` can disagree on segment and localcode for the same point, and with fresh's
whole-metre measure the two segments already resolve 1 m apart
(`research/fwa_point_snap.md`, "distance ties").

The same fwapg change also alters functions fresh calls. `fwa_locatealong()`
(`R/frs_point_locate.R:29`) and `fwa_downstreamtrace()` (`R/frs_cluster.R:330`) now take the
highest segment whose range, **closed at the top**, holds the measure, so a measure at a stream's
head is usable. `fwa_watershedatmeasure()` (`R/frs_watershed_at_measure.R:82,95`, `R/utils.R:857`)
is not itself rewritten — it has no top bound to close — but it calls
`FWA_SliceWatershedAtPoint()` on rivers, and that function's slice fraction is now clamped, so a
position near a segment's top no longer raises
`line_interpolate_point: 2nd arg isn't within [0,1]`.

Outcome: fresh adopts fwapg's tie rule in its own SQL; the effect of the pending migration on
fresh's own code paths is measured before and after and recorded in `research/`; and what the sweep
finds is pinned as live tests that skip on a database without the migration but cannot turn the
suite green when an environment variable says the database should be current.

**This issue does not migrate any database.** That waits on the upstream review.

## Decided at the gate (airvine, 2026-10-27)

1. **Trial helper:** exported from fresh, so link#383 calls it without `:::` (link already
   `Imports: fresh (>= 0.43.0)`). wet keeps its own internal copy. Named
   `frs_migration_trial()` rather than `frs_pg_trial()`, for `frs_noun_verb`.
2. **Sweep host:** the local docker fwapg on m4 (`localhost:5432`, 4,907,441 segments, `exbc` still
   in `fwa_watershedatmeasure`, no `fwapg.db_version` — the same pre-migration state as the shared
   m1 instance). Not the shared instance, because a `COMMIT` slipping through the trial would
   migrate it for everyone, and `dblink` is installed there so a rollback is not a full undo.
   (Not, as first written, because of a lock: `DROP FUNCTION` takes `AccessExclusiveLock` on the
   function object, which another session's `SELECT fwa_indexpoint(…)` does not acquire.)
3. **Migrations tried:** both pending ones, in filename order —
   `202610131654__watershedatmeasure_drop_exbc` (merged upstream as smnorris/fwapg#200) then
   `202610240132__indexpoint_tiebreak`. `frs_pg_trial()` therefore takes several files in one
   transaction, and the report names which migration each change belongs to.
4. **link:** fresh lands first; link#383 gets the measured rule, the numbers and the helper as an
   owed follow-up.

## Findings that shape the work (measured 2026-10-27)

- **Three ordering sites in `R/frs_point_snap.R`, not two.** The issue names `:419` (the
  `candidate_rank` window) and `:463` (the final order). The load-bearing one is `:446` — the
  lateral's `ORDER BY s.geom <-> p.geom, s.<col_seg> LIMIT num_features`, which decides *which*
  candidates survive, and is the only one that matters at `num_features = 1`.
- **The raw measure has to be carried through the lateral.** `c.downstream_route_measure` is
  fresh's clamped whole-metre measure (`CEIL(GREATEST(ds, FLOOR(LEAST(us, m))))`), which for two
  segments sharing a vertex gives `floor(m)` and `ceil(m)` — equal when the vertex sits on a whole
  metre, so ordering on it is not faithful. Carry `s.<col_ds>` out of the lateral under an internal
  alias (not emitted by the outer `SELECT`, so no user-visible column appears) and order all three
  sites on it, as fwapg orders on the raw `downstream_route_measure`.
- **The KNN index scan survives the new key.** `EXPLAIN` on the local fwapg with
  `ORDER BY s.geom <-> p.geom, s.downstream_route_measure DESC, s.linear_feature_id` still gives
  `Index Scan using fwa_streamnetworks_geom_idx ... Order By: (geom <-> ...)` under an
  `Incremental Sort` with the distance as `Presorted Key` — the property the roxygen at
  `R/frs_point_snap.R:381-382` protects. Record the plan in the research note.
- **Two existing SQL-string tests assert the old rule** and must be rewritten first:
  `tests/testthat/test-frs_point_snap.R:24` (`ORDER BY s\.geom <-> p\.geom, s\.linear_feature_id`)
  and `:76-77` (`ORDER BY c\.distance_to_stream, c\.linear_feature_id\) AS candidate_rank`).
- **wet#127 / PR wet#132 is the template**, on branch `origin/127-wet-station-snap-measure-the-effect-of-f`:
  `R/wet_pg_trial.R` (86 lines), `scripts/station_snap_sweep.R` (420 lines),
  `research/station_snap.md`, `tests/testthat/helper-fwapg.R`, `test-wet_pg_trial.R`,
  `test-wet_station_snap.R`. Port its refusals and its sweep shape rather than re-deriving them.
- **Call costs on the local fwapg (warm):** `fwa_locatealong` 70 ms, `fwa_downstreamtrace` 1.5 s,
  `fwa_watershedatmeasure` 2.5 s (6.3 s cold) — and `frs_watershed_at_measure()` makes two of the
  last per position. So the snap and `locatealong` runs can be exhaustive; the watershed and trace
  runs must be sampled.
- **Inputs available:** `whse_fish.pscis_assessment_svw` 19,905; `whse_fish.fiss_fish_obsrvtn_pnt_sp`
  378,971 (`bcfishobs.fiss_fish_obsrvtn_events` is empty on this host);
  `inst/extdata/crossings.csv` and `wsg_outlet.csv` for the measure side. No cached lon/lat point
  set ships with fresh, so the snap inputs are queried live.

## Revised after the Plan-agent review (2026-10-27)

`planning/active/review-plan.md` holds the review and the reasoning. What it changed, in one line
each, because these are the parts of the plan most likely to be mis-remembered later:

- Neither migration gives `fwa_watershedatmeasure` a top bound to close — it has none
  (`downstream_route_measure <= v_measure ORDER BY desc LIMIT 1`). Its provable change is that the
  tiebreak migration rewrites `FWA_SliceWatershedAtPoint`, which it calls on rivers, so a
  `line_interpolate_point: 2nd arg isn't within [0,1]` error becomes a result.
- The `frs_cluster()` pin is dropped: its trace start is always a segment's own
  `downstream_route_measure`, inside the range under either rule.
- 07FA007 is a head case, not a tie, so it belongs to Phase 4.
- `withr` moves to `Imports`; the export is named `frs_migration_trial()` for `frs_noun_verb`; its
  example is `\dontrun{}`, which is fresh's actual style for DB-dependent exports.
- The before-run drift guard becomes database-population checks plus an md5 of the before side's
  own output. "Reproduce the package's stored output" was not achievable: no such output exists.
- Three sweep states, not two, so migration attribution is measured rather than inferred.

## Phase 1 — `frs_migration_trial()`: the rolled-back migration trial

- [x] `tests/testthat/test-frs_migration_trial.R` first, ported from wet's 90-line file: the own
      `BEGIN;`/`COMMIT;` pair blanked as a pair with **line numbers preserved**; a plpgsql body's
      bare `BEGIN`/`END` and `END IF;` left alone; and the refusal list — transaction control split
      by a line break, by a `--` comment, by a `/* */` comment, after a `\r`, an unterminated
      `COMMIT` at end of input, a 40-dash comment run and a 20-block-comment run (the PCRE
      match-limit cases), each refusal naming the line; plus `dblink_exec`,
      `COPY ... FROM PROGRAM`, `setval`, `pg_background_launch`.
- [x] `R/frs_migration_trial.R`: exported `frs_migration_trial(conn, files, env = parent.frame())`
      and internal `.frs_migration_trial_sql(sql)`. Port wet's possessive/atomic comment grammar
      and keyword set (`BEGIN`, `START TRANSACTION`, `COMMIT`, `END`, `ROLLBACK`, `ABORT`,
      `PREPARE TRANSACTION` with their option trailers), `\z` rather than `$` under `(?im)`, and
      **a `gregexpr()` warning treated as a refusal** (a regex that gave up has not looked).
- [x] `files` is a vector: one `DBI::dbBegin()`, each file stripped and applied in order with
      `DBI::dbExecute(conn, body, immediate = TRUE)` — `immediate` is load-bearing, since RPostgres
      otherwise prepares the statement and a prepared statement cannot carry multiple commands
      (these bodies are 1,369 and 895 lines with `$$` / `$function$` quoting). One
      `withr::defer(DBI::dbRollback(conn), envir = env)`. Record `pg_current_xact_id()` before and
      compare with `pg_current_xact_id_if_assigned()` after **each** file; equal passes, NULL/NA
      (a commit opened a fresh unassigned transaction) and a different id both refuse.
- [x] `DBI::dbBegin()` fails on a connection already in a transaction: say so in the roxygen, and
      check it in both callers (Phase 3's script and Phase 4's helper).
- [x] Promote `withr` from `Suggests` to `Imports`. The function is exported and link will call it
      from an installed package, where a suggested dependency is not guaranteed; link has `withr`
      in `Suggests` only.
- [x] roxygen with a `\dontrun{}` example — fresh's actual style for DB-dependent exports
      (`R/frs_point_locate.R:16-22`); there is no `@examplesIf` anywhere in `R/`, and R-CMD-check
      runs examples on every PR. Document the limits: a rollback does not undo work committed on
      another connection (`dblink` is installed on the shared fwapg), `COPY ... PROGRAM`,
      `setval()`/`nextval()`, or files written server side; and that a refusal after file *n* ran
      is undone by the already-registered deferred rollback, not by the refusal.
- [x] Two live tests: a table a trial creates is visible on the trial's connection, invisible on a
      second connection, and gone on both after the frame exits; and a migration with a mid-file
      `COMMIT;` is refused **before anything runs** (`to_regclass` still NA).

## Phase 2 — the tie rule in `frs_point_snap()`

- [x] Rewrite the two SQL-string assertions (`test-frs_point_snap.R:24`, `:76-77`) and add one for
      the final `ORDER BY`, to the new rule. They fail against the current code. These are the
      only two assertions in the suite that encode the old rule (grepped: no `_snaps/`, no test
      asserts a snapped `linear_feature_id`).
- [x] `.frs_point_snap_sql()`: carry `s.<col_ds>` out of the lateral under an internal alias —
      **distinct from `col_ds` itself**, or `s.*` yields two columns of that name and
      `c.downstream_route_measure` becomes ambiguous — and order all three sites on it:
      `:446` `ORDER BY s.geom <-> p.geom, s.<col_ds> DESC, s.<col_seg>`;
      `:419` `ORDER BY c.distance_to_stream, c.<alias> DESC, c.linear_feature_id`;
      `:463` `ORDER BY c.id, c.distance_to_stream, c.<alias> DESC, c.linear_feature_id`.
      The outer `SELECT` list is explicit, so no new column reaches the caller or the `to =` table.
      The alias is not covered by the `cols_out` collision check at `:163-166`; a qualified
      `c.<alias>` in `ORDER BY` resolves to the input column, so a user `col_id` of the same name
      is safe — note it rather than relying on that check.
- [x] Keep `candidate_rank`'s window order and the final `ORDER BY` identical. A third assertion
      depends on it: `test-frs_point_snap.R:464-470`, `expect_equal(d$candidate_rank, seq_len(nrow(d)))`.
      State this as the invariant so a later edit to one site and not the other fails loudly.
- [x] Re-measure the two tie points through `.frs_point_snap_sql()` on the local docker, once on
      `main`'s SQL and once on the new SQL, **before** writing any id as an assertion. wet's ids
      came from `fwa_indexpoint()`, which returns one candidate per `blue_line_key`; fresh returns
      candidates per **segment** and applies its own `999`/NULL-localcode/`1425` guards, so the
      ids and the ranks are not transferable.
- [x] Live tests at the two tie points (WGS84): **08KD006** (-122.373062133789, 54.0455589294434),
      a tie on Willow River blue line 356360570 between 703862843 and 703862887; **07EA001**
      (-125.626388549805, 57.4208297729492) on blue line 359014591 — which needs
      `num_features > 1` or `col_blk = 359014591` for its stream's tie to surface at all. These
      test fresh's own SQL, so they gate only on a connection — **no migration needed** — and each
      is shown red before the change. 07FA007 is a head case and belongs to Phase 4.
- [x] Re-verify the five live test files that consume the snap's pick at the Bulkley points, in
      case any of those points is a tie: `test-frs_network_downstream.R:37`,
      `test-frs_network_prune.R:35` and `:54`, `test-frs_network_upstream.R:54`,
      `test-frs_point_locate.R:7`, `test-frs_break.R:258`.
- [x] Update the roxygen prose at `R/frs_point_snap.R:11-12` and `:378-382`, **and `CLAUDE.md:213`**
      under "Point snap", which names `linear_feature_id` as the tie-break.
- [x] `EXPLAIN` the new lateral on the local fwapg and keep the plan for the research note.
- [x] Confirm `num_features = 1` and `> 1` agree on which candidate ranks first.

## Phase 3 — the sweep, before and after

- [x] `data-raw/point_snap_tie_sweep.R`, in the genre of `data-raw/point_snap_parity_check.R`:
      header naming the issue, what is compared and a literal `Usage:` block;
      `pkgload::load_all()`; `commandArgs()` with validated defaults; scratch tables in `working.`
      dropped at the **start** as well as the end (`on.exit()` does not fire at a script's top
      level under `Rscript` — `point_snap_parity_check.R:46-49`); outputs to
      `data-raw/logs/indexpoint_266/`.
- [x] Connect to the local docker fwapg explicitly (`Sys.setenv()` / `FRESH_PG*`, never the
      inherited `PG*`, which points at the shared instance). The reason the trial stays off the
      shared instance is **not** a lock — `DROP FUNCTION` takes `AccessExclusiveLock` on the
      function object, which another session's `SELECT fwa_indexpoint(…)` does not acquire. It is
      that a `COMMIT` slipping through would migrate a shared database for everyone, and `dblink`
      is installed there, so a rollback is not a full undo. Do not run
      `scripts/habitat/habitat_province.R` or `habitat_benchmark_island.R` during a sweep: both
      hardcode `localhost:5432`.
- [x] Migration files copied to `tempdir()` and md5'd **before any connection**, with the fwapg
      commit required as `^[0-9a-f]{7,40}$`, so a file rewritten mid-run cannot be credited with
      the counts.
- [x] Refuse to start when the database already has the rework
      (`pg_get_function_arguments('whse_basemapping.fwa_indexpoint'::regproc)` names
      `include_disconnected`) — there is no before to measure. Record the base: `exbc` still in
      `fwa_watershedatmeasure`, no `fwapg.db_version`.
- [x] **Three sweep states on three trial connections**, so attribution is measured, not inferred:
      base; `202610240132__indexpoint_tiebreak` alone; both migrations in filename order. Each
      trial runs inside a function whose **return** fires the rollback (a top-level
      `withr::defer(…, envir = globalenv())` never fires under `Rscript`), asserts
      `include_disconnected` is present before sweeping, and a fourth connection afterwards
      asserts the old signature is back.
- [x] Batch the per-measure calls: one set-returning query per chunk,
      `… FROM (VALUES …) v(blk, m) LEFT JOIN LATERAL whse_basemapping.fwa_locatealong(v.blk, v.m) w ON TRUE`.
      `LEFT JOIN LATERAL … ON TRUE` is **mandatory** — a plain `CROSS JOIN LATERAL` makes a miss
      vanish instead of counting it, and misses are the number the sweep exists to produce. Both
      the old and new `fwa_locatealong` are `plpgsql IMMUTABLE STRICT PARALLEL SAFE` (verified), so
      the two sides' timings are comparable. `SAVEPOINT` per **chunk**, `SET LOCAL
      statement_timeout` once per transaction, and on a chunk error re-run that chunk row by row
      under per-row savepoints. Stop the run if any captured message says
      `current transaction is aborted`.
- [x] Inputs, with sizes stated and a reproducible sampling rule (`ORDER BY md5(<id>::text) LIMIT n`):
      all 19,905 PSCIS and 5,000 of `whse_fish.fiss_fish_obsrvtn_pnt_sp` through
      `frs_point_snap()` (tolerance 150, `num_features = 5`); `fwa_locatealong()` batched over
      every resulting position and over 20,000 measures sampled from `inst/extdata/crossings.csv`
      plus all of `falls.csv` and `wsg_outlet.csv`; `frs_watershed_at_measure()` and
      `fwa_downstreamtrace()` over every tied or changed position plus 200 sampled positions
      (≈5 s and ≈1.5 s per position per state — budget it and record the elapsed time).
      `crossings.csv`'s measures are bcfishpass's own fractional indexing, so label that part of
      the report as measuring the migration at the fwapg level: fresh never emits a fractional
      measure.
- [x] Count the three things the issue asks for: positions where `fwa_locatealong()` or
      `fwa_watershedatmeasure()` returns nothing; points tied on two segments of one stream
      (measured once, on the base side — the migration cannot change the geometry); calls that
      error, by message. Count the two head cases separately (a whole-metre top, and a segment
      shorter than a metre).
- [x] Drift guard, in place of "reproduce the package's stored output" (no such stored output
      exists — the parity numbers were a fresh-vs-link comparison and link is not installed):
      assert the database-population figures `research/fwa_point_snap.md` records, which are
      independent of fresh's tie rule — 4,907,441 segments; 208,189 `999.*` of which 37,416 have a
      non-NULL localcode; 2,989,828 candidate segments starting at a fractional measure; 246
      shorter than a metre — and write an md5 of the base side's own sorted
      `(id, blue_line_key, measure)` output into the log, so this run and any later run are
      comparable byte for byte.
- [x] Tracked report (`.txt` + `_summary.csv`) in `data-raw/logs/indexpoint_266/`: a
      non-reproducible **header** (migration files, md5s, fwapg commit, "applied inside a
      transaction and rolled back", the base, elapsed times) and a reproducible **body** (the
      three-state count table, errors by message, ties, and the positions whose segment,
      `fwa_locatealong()` or watershed changed, each attributed to the state that changed it). A
      second full run must be byte-identical **in the body**; the comparison excludes the header.

## Phase 4 — live tests and the gate

- [x] `tests/testthat/helper-db.R`: a connector of its own — `frs_fwapg_conn()` reading
      `FRESH_PGHOST`/`PORT`/`DATABASE`/`USER`/`PASSWORD` with `localhost`/`5432`/`fwapg`/`postgres`
      defaults, ported from wet's `helper-fwapg.R` — so the trial never reaches the shared
      instance via `frs_db_conn()`. Then `frs_indexpoint_current(conn)` (the
      `pg_get_function_arguments` check, **wrapped in `tryCatch`**: `'…'::regproc` throws when the
      function is absent or ambiguous, which on the skip path would be a test error rather than a
      skip), `frs_fwapg_current_wanted()` (reads `FRESH_FWAPG_CURRENT`), and
      `local_fwapg_indexpoint(env = parent.frame())` which applies `FRESH_FWAPG_TRIAL` via
      `frs_migration_trial(conn, trial, env = env)` — **`env` passed through**, or the rollback
      fires before the test body — `stop()`s on a path that names no file (testthat runs from
      `tests/testthat`, so it must be absolute), and otherwise skips naming the missing migration.
      The helper owns the disconnect, and every `on.exit()` in a gated test uses `add = TRUE`: a
      bare `on.exit()` replaces the handler list and would discard the deferred rollback.
- [x] Pin 1, by construction rather than by what the sweep happens to catch: query for a
      top-of-blue-line segment whose `upstream_route_measure` is an exact integer, then
      `frs_point_locate(conn, blk, us)` returns 0 rows before the tiebreak migration and 1 row
      under the trial — the new `fwa_locatealong` compares
      `round(s.upstream_route_measure::numeric, 4) >= round(v_measure::numeric, 4)`.
- [x] Pin 2: a river position near a segment's top where `frs_watershed_at_measure()` raises
      `line_interpolate_point: 2nd arg isn't within [0,1]` before the tiebreak migration and
      returns a polygon under the trial. The path is `fwa_watershedatmeasure` →
      `FWA_SliceWatershedAtPoint` (verified in the installed body), which the migration rewrites to
      clamp its slice fraction. Ids from the Phase 3 report; if the sweep finds none, construct one
      the same way as pin 1.
- [x] Pin 3, attributed to the **other** migration: a position with an upstream border crossing
      whose `frs_watershed_at_measure()` area changes when
      `202610131654__watershedatmeasure_drop_exbc` is applied. Skipped unless that migration is in
      `FRESH_FWAPG_TRIAL` too.
- [x] One test that **fails rather than skips** when `FRESH_FWAPG_CURRENT=true`: the
      `if (!frs_fwapg_current_wanted()) skip(...)` guard **before** the connect, its own
      connection, no `skip_if_no_conn()`, no `local_fwapg_indexpoint()`, no trial — so an
      unreachable database errors and a stale one fails. Keep it away from any test that sets trial
      state. Verify by running it against this pre-migration database with the variable set: red.
- [x] **Amend** CLAUDE.md's existing "Testing on alternate hosts" section with the `FRESH_PG*`
      connector, `FRESH_FWAPG_TRIAL` (absolute path) and `FRESH_FWAPG_CURRENT`.

## Phase 5 — research note and bookkeeping

- [x] Revise `research/fwa_point_snap.md`: the `distance ties` row becomes the new rule for both
      fwapg and fresh (link's stays until link#383); stamp the two passages that measured the old
      rule — the "22 equidistant ties" parity bullet and the closing "resolves 1 m apart depending
      on which segment wins the tie" — as measured against fresh 0.40.0 and link 0.50.0, since
      link is not installed and they cannot be re-run. Add sections for what each migration changes
      by cause, the base the trial ran on, and what it does not fix (including the two findings
      that cost Phase 4 two pins: `fwa_watershedatmeasure` has no top bound, and `frs_cluster()`'s
      trace starts are segment lower bounds). Provenance line in house style: date, issue, script,
      log dir, migration filenames + md5s, fwapg commit.
- [x] Refresh the `research/README.md` index row.
- [x] `devtools::document()`, `lintr::lint_package()`, `devtools::test()` (grepped in one call).
- [x] `NEWS.md` entry and `DESCRIPTION` version bump as the **final** commit of the branch.

## Owed at the end (reported, done after merge)

- [ ] link#383: hand it the measured rule, the sweep numbers and `fresh::frs_migration_trial()`.
- [ ] Migrating any database waits on NewGraphEnvironment/fwapg#41 / smnorris/fwapg#201 — not this
      issue, and not this branch.
- [ ] Whether wet's internal copy collapses onto `fresh::frs_migration_trial()` is wet's call; note
      it on wet#132 rather than changing wet here.

## Validation

- [x] Tests pass (`Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5`)
- [x] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved:

- **The tie rule:** the three rewritten SQL-string tests fail on `main` and pass after; the two
  tie-point live tests return the upper segment first where `main` returns the lower, with the ids
  re-measured through fresh's own snap on both versions; `EXPLAIN` shows the KNN index-ordered scan
  intact; the five dependent live files still pass.
- **`frs_migration_trial()`:** the ported refusal cases (each a migration body that must not run);
  the live test proving a trial's table is invisible to a second connection and gone after; the
  post-rollback assertion in the sweep that `fwa_indexpoint`'s old signature is back.
- **The sweep:** the population drift guard holds; the report body is byte-identical on a second
  run; no `current transaction is aborted` in any captured message; every counted change is
  attributed to the state that produced it.
- **The gate:** the `FRESH_FWAPG_CURRENT=true` test is red against this un-migrated database, and
  each pin is red without the trial and green with it.

---

Branch `266-frs-point-snap-fwapg-s-tie-rule-and-a-sw`, off `main` at db65bdd. Plan approved at the
gate on 2026-10-27 and revised the same day after the Plan-agent review in
`planning/active/review-plan.md`.
