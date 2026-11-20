# Plan review — #293 (Plan agent, 2026-11-02)

Spawned in plan mode with the design sketch and the #282 precedent; read-only, so the
findings came back as reply text and are recorded here. My verdict sits under each.
Every file:line it cited was checked against the tree before the plan was written.

## Blockers

**B1 — "the `id_segment` join is safe again" is false, and it is the hinge.** Today's
group-keyed delete (`frs_near_river.R:156-158`, `frs_habitat_classify.R:249-255`) is
what makes `(id_segment, watershed_group_code)` a sound *read* key on these shared
tables: after a job runs, the table holds no other job's rows for that job's groups. An
lfid-keyed delete clears only the ground the job covers, so for the first time the table
can hold same-group rows from another job whose ids were derived independently — and
`research/id_segment_identity.md:88-91` measured 81 of 275 derived ids equal to a real
*same-group* `linear_feature_id`. Newly exposed: `.frs_near_river_sql()`
(`utils.R:477-487`) can satisfy its `EXISTS` from a stale row for different ground, and
every `(id_segment, watershed_group_code)` join against the habitat table can read
another job's row — `frs_habitat.R:1401,1441,1472,1534,1806,1944`,
`frs_cluster.R:276,399,474,510,583`. The canonical case is the repair the NEWS
recommends: a whole-group BULK run, then `frs_habitat(wsg = "BULK", aoi = <sf>)`.

> **Verdict: confirmed, and it reshaped the plan.** Verified the join shape at 13 sites;
> all are uniformly `h.id_segment = s.id_segment AND h.watershed_group_code =
> s.watershed_group_code`, so the edit is one `AND` line per site from one builder.
> Phase 4 exists because of this finding. Without it #293 converts a data-loss bug into
> a silent wrong-row bug.

**B2 — an unconditional `linear_feature_id` column breaks non-FWA networks.**
`.frs_persist_delete_key()` errors on a one-sided mismatch (`utils.R:1247-1253`), so if
the habitat/near_river DDL always creates the column, `frs_habitat_classify()` silently
acquires `linear_feature_id` as a hard requirement on `table`, which its docs
(`frs_habitat_classify.R:16-18`) do not ask for. Live proof:
`test-frs_habitat_classify.R:364-369` builds `working.Test_220_Empty` with no
`linear_feature_id` and asserts `expect_no_error()` twice.

> **Verdict: confirmed.** Read the fixture; it has no `linear_feature_id`. The column is
> created only when the source carries it, which keeps the chooser's `id_segment` branch
> reachable and the one-sided error for genuine disagreement.

**B3 — `.frs_persist_columns()` is not reusable here.** It aligns the target to *all* of
the source's columns (`utils.R:1124-1130`); the habitat and near_river tables are
projections, so it would `ALTER ADD COLUMN geom`, `gradient`, `blue_line_key` onto
`to_habitat`. Only the chooser, the SQL builder and the NULL-key guard are reusable.

> **Verdict: confirmed from the code.** Explicit `ALTER TABLE ... ADD COLUMN IF NOT
> EXISTS` instead.

## Ordering

- **O1** — `species_params` is built at `:260-273`, *after* the delete, so step 3 needs
  step 5's move. `sp_classify` (`:204-206`) already computes the same set with the same
  predicate; derive one from the other or ship a drift hazard.
- **O2** — the habitat NULL-key guard must run with the other pre-flight checks
  (`:209-233`), not at the delete: the near_river walk itself *writes*, so a legacy
  habitat table would otherwise be refused only after the full walk. Keep the near_river
  shape check first, or `test-frs_habitat_classify.R:435-505` stops seeing its four
  messages.
- **O3** — keep `CREATE TABLE` and `.frs_index_working(conn, to)` outside the
  transaction. `CREATE INDEX` takes SHARE on the shared target, which conflicts with
  another mirai worker's open ROW EXCLUSIVE; inside the transaction that is a two-worker
  deadlock shape.
- **O4** — the guard must not fire when `overwrite = FALSE`; no delete runs then.

> **Verdict: all four accepted into Phase 3 as written.** O3 is the one I had not
> considered and is the reason the plan pins what stays outside the transaction.

## Gaps

- **G1** — `.frs_persist_delete_sql()` returns a finished statement, so it needs a
  nullable extra-predicate argument for `species_code`; near_river has no such column.
  Its same-relation guard (`utils.R:1285-1290`) is a free bonus on the habitat path,
  catching `frs_habitat_classify(table = X, to = X)`, which nothing checks today.
- **G2** — nothing validates that `wsg_code` is the group the table holds. `wsg_codes`
  is already in hand at `:170-172`: assert `length(wsg_code) == 1` and
  `setequal(wsg_codes, wsg_code)`, or the new parameter reintroduces #293.
- **G3** — `.frs_near_river_table()` builds its own indexes (`frs_near_river.R:327-333`)
  and never calls `.frs_index_working()`, so it needs `(linear_feature_id)` added; the
  habitat table gets one free from `utils.R:640-644`.
- **G4** — add `linear_feature_id` to `.frs_near_river_check()`'s `cols_need`
  (`frs_near_river.R:233-237`), turning a late chooser error into the existing up-front
  named-column one.
- **G5** — for the walk's lfid, join the walk table back to `table` on
  `(id_segment, watershed_group_code)` in the INSERT rather than threading the column
  through `.frs_near_river_walk_sql()`, which `test-frs_near_river.R:245-247` and
  `data-raw/near_river_check.R:123-124` call positionally.
- **G6** — two more exported writers of the habitat table joining on
  `(id_segment, watershed_group_code)`: `frs_order_child()`
  (`frs_order_child.R:291-313`) and `frs_habitat_overlay()`
  (`frs_habitat_overlay.R:269-290`, which also discovers species with an unscoped
  `SELECT DISTINCT species_code FROM <to>` at `:196-200`). Also
  `frs_cluster(species = NULL)` resolves species from the habitat table scoped to the
  group (`frs_cluster.R:139-147`), so a stale species' rows now survive and get
  clustered against the wrong streams table.
- **G7** — the per-species progress line (`:404-409`) counts via `.frs_wsg_in(table)`,
  the whole group, so surviving rows from other jobs inflate it. Key it on the delete
  key. `test-frs_habitat_classify.R:508-538` exists to pin exactly this kind of count.

> **Verdict: G1-G5 and G7 accepted into Phases 2-3.** G6 is the honest scope question:
> the plan fixes the sites classify's own pipeline drives and decides per site whether
> `frs_order_child()` and `frs_habitat_overlay()` direct mode are fixed here or filed
> against #277 — filed rather than half-fixed.

## Assumptions

- **A1** — mirai workers each hold their own connection (`frs_habitat.R:580-582`), so
  `dbBegin` is per-worker and jobs in different groups touch disjoint rows. Verify O3,
  and that the DELETE's dead tuples, unreclaimable until commit, are tolerable on a
  shared `to_habitat`. The first-run `CREATE TABLE IF NOT EXISTS` race is pre-existing.
- **A2** — `.frs_run_connectivity()` is unaffected by the transaction: it runs after
  classify returns and only `UPDATE`s habitat rows; its `INSERT INTO`s all target
  `pg_temp`. Replicate `.frs_persist_streams()`'s `on.exit` rollback
  (`utils.R:1419-1432`) so an error cannot leave an open transaction for it to inherit.
- **A3** — the documented whole-table call (`frs_habitat_classify.R:99-102`) becomes
  `linear_feature_id IN (SELECT ... FROM fresh.streams)` over 3.8M values where it was
  98 cheap column filters. Measure before shipping; document `wsg_code` as the
  whole-group opt-in.

> **Verdict: accepted.** A3 is a Phase 6 measurement with a documented remedy.

## Failure modes of species-scoping the delete

- **F1** — a species X row left behind by a Y-only run keeps the `id_segment` the *old*
  working table derived, while `to_streams` has been replaced for that ground with newly
  derived ids (`frs_break.R:697-701`; `id_segment_identity.md:79-82`). So it does not
  merely go stale, it mis-joins. Adding `linear_feature_id` narrows it to "ambiguous
  within a parent" rather than "wrong parent" — an improvement, not a fix.
- **F2** — species-scoping makes the staged migration un-completable: the NULL-key guard
  counts over the whole table by design (`utils.R:1352-1360`), so rows for a species the
  user no longer models keep NULL lfid forever and every later custom-AOI run keeps
  raising. Resolve explicitly — leave the whole-group delete unscoped by species, or
  offer a one-shot backfill (on a `fresh.streams`-era table `(id_segment,
  watershed_group_code)` has 0 duplicate pairs, so an `UPDATE ... FROM <to_streams>` on
  both columns is valid there), or say the remedy is to drop the table.
- **F3** — no call now removes an orphaned species' rows, so with F1 that is a
  silently-wrong row set rather than just a stale one. Document or give an escape.
- **F4** — a hand-built row with NULL `species_code` survives every run, and the
  NULL-key guard checks only the delete key.

> **Verdict: F2 changed a gate decision.** The owner had approved species-scoping; F2
> shows a species-scoped *whole-group* delete cannot complete the backfill the migration
> posture advertises, so gate decision 4 restricts species scoping to the custom-AOI
> key. F1/F3/F4 are documented residuals, with F1/F3 filed as a sibling of #218.

## Test breakage, as enumerated by the reviewer

`test-frs_near_river.R:270-285` (and its positional 6-value `INSERT` at `:277-279`);
`test-frs_habitat.R:783` (`spec$partition_wsg` pinned at 2 — reuse the existing
`wsg_code` local and it stays green), `:774-775` (the chooser call must stay in
`.frs_persist_streams`), `:647-731` (a good home for the #293 decoy);
`test-utils.R:673-689` (the guard's exact message text, both branches, so the shared
helper needs `cols_added`); `test-frs_habitat_classify.R:350-387` (B2), `:508-538`
(`DBI::dbBegin("mock")` is not routed through the mocked `.frs_db_execute`, so guard the
transaction on `inherits(conn, "DBIConnection")`), `:435-505` (becomes partly vacuous
unless the `pg_temp.nr_hab` fixture gains the column);
`test-near_river_rules.R:19-23` and `test-near_river_inherit.R:48-54` (the exact `EXISTS`
string); `helper-synthetic.R:39-43,75-80,91-95` plus
`test-frs_connectivity_wsg.R:351-354,684-686` — the largest mechanical cost, and the one
the first draft of the design did not account for.

> **Verdict: taken as Phase 5's checklist, to be re-derived from the tree rather than
> trusted line by line.**
