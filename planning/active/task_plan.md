# Task: Custom-AOI jobs delete whole watershed groups from the shared habitat and near_river tables (#293)

## Context

`frs_habitat_classify()` takes its delete scope from the group codes its working
table mentions (`R/frs_habitat_classify.R:168-172`) and then deletes those groups
**whole** from the shared output (`:249-255`). In WSG mode that is a clean replace.
In custom-AOI mode the working table holds only the AOI's segments while the groups
it names extend far beyond it, so the delete removes rows the job will not put back —
on the shipped example (`man/frs_habitat.Rd:211-217`) a sub-basin's run against five
whole groups. `frs_near_river()` has the identical shape (`R/frs_near_river.R:154-158`)
into a target derived from `to` (`frs_habitat_classify.R:208`), so it is shared too.

This is not #231/#277/#282's mechanism (an `id_segment` predicate missing
`watershed_group_code`). Here the predicate names the group correctly and the *group
set* is too wide. #282 settled the same defect class on `to_streams` and left this one
filed, because its key — the parent FWA segment `linear_feature_id` — is not a column
these two targets carry (`research/id_segment_identity.md`).

## Decided at the gate (owner, 2026-11-02)

1. **Key: option (a).** Widen the habitat and `near_river` schemas to carry
   `linear_feature_id` and key the delete on it, reusing #282's chooser unchanged.
   The only key measured correct against both table generations and the only one that
   clears stale sub-segments. (b) narrows the loss but keeps a measurably smaller
   version of it (81 of 275 derived ids equalled a real same-group `linear_feature_id`);
   (c) reaches far beyond these functions.
2. **Migration: hard error, staged backfill.** `ALTER ADD COLUMN`, then raise if any
   row holds NULL for the key, naming the repair — re-run each group with `wsg` and no
   `aoi`. #282's posture, including its measured avoidance of a one-shot proxy guard.
3. **Species: scope the delete to the species the job inserts** (`species_params`, not
   the `species` argument), matching the roxygen contract at `:75-78`.
4. **Refinement to 3, decided here, not asked:** the **whole-group** (`wsg` mode)
   delete stays **unscoped by species**. A species-scoped whole-group delete makes the
   staged backfill in decision 2 un-completable — rows for a species no longer modelled
   keep NULL `linear_feature_id` forever and every later custom-AOI run keeps raising.
   Species scoping therefore applies to the custom-AOI key only, which is #293's
   subject; `wsg` mode keeps today's wholesale replace, which the issue names as the
   repair path for damage already done. `overwrite`'s roxygen states the difference.

## The finding that reshaped the plan (plan review, verified)

Today's whole-group delete is what makes `(id_segment, watershed_group_code)` a sound
**read** key on these shared tables: after a job runs, the table holds no other job's
rows for that job's groups. An lfid-keyed delete removes that property — a whole-group
BULK run followed by `frs_habitat(wsg = "BULK", aoi = <sf>)` correctly leaves the
whole-group rows in place, and the AOI job's independently derived ids then collide
with them inside one group (81 of 275, measured). So the reads must gain the same key
or #293 becomes a silent wrong-row bug. Verified: 13 sites join habitat to a streams
table on `h.id_segment = s.id_segment AND h.watershed_group_code = s.watershed_group_code`
(`R/frs_cluster.R:226,312,470`, `R/frs_habitat.R:1402,1475,1537,1909,1946`,
`R/frs_order_child.R:300`, `R/frs_habitat_overlay.R:271`), plus the `near_river`
predicate (`R/utils.R:477-487`). **Phase 4 is therefore part of the fix, not an extra.**

The column must be **conditional on the source carrying it**: `frs_habitat_classify()`
does not require `linear_feature_id` today and a live test proves it
(`tests/testthat/test-frs_habitat_classify.R:364-369` builds a streams table without
one and asserts `expect_no_error()` twice). An unconditional column would make
`.frs_persist_delete_key()`'s one-sided-mismatch error fire for every non-FWA network.

## Phase 0 — Measure the exposure

- [x] `data-raw/audit_habitat_293.R`, in the shape of `data-raw/audit_persist_282.R`:
      every habitat and `near_river` table reachable through `frs_db_conn()`, its
      columns, row count, group count, species count; and for any multi-group one, the
      per-group shortfall against `to_streams` that the loss would leave.
- [x] The issue's unmeasured ratio: rows a custom-AOI job over the documented AOI would
      delete vs. reinsert.
- [x] Rows that would need `linear_feature_id` backfilled, per table.
- [x] Record in `findings.md`. (Measured already on the `bcfishpass` instance: four
      fresh-written habitat tables, all single-group, none carrying
      `linear_feature_id`, no `near_river` table at all — so no loss there, and the
      migration cost on it is nil. `frs_db_conn()`'s instance, which holds
      `fresh.streams`, is the one still to audit.)

## Phase 1 — Tests first (failing)

- [x] Defect 1: a shared habitat target holding one group's rows for ground **outside**
      a custom AOI survives a custom-AOI classify.
- [x] Defect 2: a same-group row at an `id_segment` the job's derived ids reach, on a
      **different** `linear_feature_id`, survives. Assert the collision is live before
      asserting survival, as `test-frs_habitat.R:647` does.
- [x] Both again for `near_river`.
- [x] Read side: a surviving same-group row for other ground must not satisfy a
      `near_river` predicate, nor be read by `.frs_run_connectivity()`, for this job's
      segments.
- [x] Non-FWA: a streams table without `linear_feature_id` still classifies
      (`id_segment` key), and the targets gain no column.
- [x] Migration: a legacy habitat table raises, naming the repair; the `wsg` re-run
      backfills it; a legacy `near_river` table is refused by the shape check.

## Phase 2 — Schema and key

- [x] `linear_feature_id bigint` on the habitat DDL (`frs_habitat_classify.R:236-246`)
      and `.frs_near_river_table()` (`frs_near_river.R:316`), **only when the source
      carries it**; written from the working table in both INSERTs. For the walk, join
      the walk table back to `table` on `(id_segment, watershed_group_code)` rather
      than threading the column through `.frs_near_river_walk_sql()`, whose signature
      two callers use positionally.
- [x] `(linear_feature_id)` index in `.frs_near_river_table()`; the habitat table gets
      one free from `.frs_index_working()` (`utils.R:640-644`).
- [x] ~~`linear_feature_id` into `.frs_near_river_check()`'s `cols_need`~~ —
      **not done, and should not be**: the column is conditional on the source
      carrying it, so requiring it would refuse every non-FWA network. The
      refusal it was meant to give is in `.frs_near_river_check_shape()`
      instead, which compares the two tables rather than demanding a column.
- [x] Extend `.frs_near_river_check_shape()` to refuse a table without the column —
      remedy "drop it and re-run", which is cheap for a derived cache.
- [x] Reuse `.frs_persist_delete_key()` / `.frs_persist_delete_sql()`; the latter gains
      a nullable extra-predicate argument for `species_code`. Do **not** reuse
      `.frs_persist_columns()`: it aligns *all* of the source's columns and would
      `ALTER` `geom` and friends onto the habitat table. Explicit
      `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` instead.
- [x] Factor the NULL-key guard out of `.frs_persist_streams()` into one shared
      internal helper taking `key` and `cols_added`, so the three sites cannot drift.
      Keep the chooser call inside `.frs_persist_streams()` — `test-frs_habitat.R:774`
      pins it — and preserve both message branches, which `test-utils.R:673-689` pins.

## Phase 3 — Delete scope, ordering and atomicity

- [x] `wsg_code = NULL` on `frs_habitat_classify()` and `frs_near_river()`;
      `frs_habitat()` passes its existing `wsg_code` local (`frs_habitat.R:405`, `:587`)
      at both classify sites, which keeps `test-frs_habitat.R:783`'s pin at 2.
- [x] Validate it: `length(wsg_code) == 1` and `setequal(wsg_codes, wsg_code)`, or a
      whole-group delete on a table spanning groups reintroduces #293 through the new
      parameter.
- [x] Replace both deletes with the chosen key; species predicate on the custom-AOI key
      only (gate decision 4).
- [x] Derive `species_params` once, above the near_river checks, and define
      `sp_classify` (`:204-206`) from it — the two compute the same set with the same
      predicate today.
- [x] Move the delete down to immediately precede the inserts, and wrap delete +
      per-species inserts in one transaction, following `.frs_persist_streams()`'s
      `dbBegin` / nested-transaction / `on.exit` rollback handling exactly. Keep
      `CREATE TABLE` and `.frs_index_working()` **outside** it: `CREATE INDEX` takes
      SHARE on the shared target and would deadlock against another mirai worker's
      open ROW EXCLUSIVE. Guard the transaction on `inherits(conn, "DBIConnection")`,
      the precedent at `utils.R:572`, or `test-frs_habitat_classify.R:508` breaks on
      its mock connection.
- [x] Hoist the habitat pre-flight (create, ALTER, column read, chooser, NULL count)
      up beside the other checks at `:209-233`, after the near_river shape check, so a
      legacy table is refused before the walk writes anything and before
      `test-frs_habitat_classify.R:435` stops seeing the four messages it matches.
- [x] No guard when `overwrite = FALSE` — no delete runs.
- [x] Key the per-species progress count (`:404-409`) on the delete key, not the group:
      surviving rows from other jobs in the group would otherwise inflate it.

## Phase 4 — The read side

- [x] One internal builder for the habitat↔streams join predicate, conditional on both
      tables carrying `linear_feature_id`, applied at all 13 sites enumerated above.
- [x] `.frs_near_river_sql()` (`utils.R:468`) gains the same key; thread the choice
      through `frs_habitat_predicates()` as one new defaulted argument (exported, so
      backward compatible, and link checks only for named formals).
- [x] Enumeration test over the parsed functions: no habitat↔streams join is left on
      `id_segment` + `watershed_group_code` alone where the lfid key is available.
      Terminate on the enumeration, not on a quiet review round.
- [x] `frs_order_child()` and `frs_habitat_overlay()`'s **bridge** mode are fixed
      here (both take a streams table, so the key is available). Overlay's
      **direct** mode keys on the caller's `by` and stays #277's question.

## Phase 5 — Fixtures and the test sweep

- [x] `tests/testthat/helper-synthetic.R:39-43` is a second habitat DDL whose comment
      claims one shape for all habitat fixtures: add the column and update its
      positional inserts (`:75-80`, `:91-95`), plus
      `test-frs_connectivity_wsg.R:351`, `:684`.
- [x] `test-frs_near_river.R:270` ("only the table's groups are replaced") — rewrite
      for the new key; its positional 6-value `INSERT` fails on a 7-column DDL.
- [x] ~~`test-near_river_rules.R:19` and `test-near_river_inherit.R:48` pin the exact
      `EXISTS` string.~~ — **no change needed**: `near_river_lfid` defaults to
      `FALSE`, which builds byte-identically to 0.53.0, so both pins stay green.
- [x] `test-frs_habitat_classify.R:443` — add the column to the `pg_temp.nr_hab`
      fixture so its "nothing is touched before the walk" case stays non-vacuous.
- [x] ~~Add the #293 decoy to the #282 integration test~~ — done instead as its own
      end-to-end test in `test-habitat_partition_293.R` (outer AOI, then inner AOI,
      into one shared pair), which asserts the surviving rows **and** that two jobs'
      rows now coexist in one group. Three more landed with it: the near_river shape
      refusal both ways, species scoping, and the delete/insert transaction.

## Phase 6 — Docs, measurement and follow-ups

- [x] `A3`: **measured and disproved** — one semi-join plans at ~1.03M against 98
      group filters at ~80K each (~7.9M total), so the new form is cheaper for a
      whole-province run and more expensive per group, which is what `wsg_code` is
      for. `findings.md` has the plans. The example gains a `wsg_code` block and the
      view's join key gains the parent segment.
- [x] roxygen: `overwrite`'s mode-dependent species semantics (decision 4); the two
      residual limits — a stale species' rows keep an `id_segment` from an earlier
      numbering, so they are ambiguous *within* a parent (`F1`), and no call now
      removes an orphaned species' rows (`F3`).
- [ ] `NEWS.md` + version bump as the final commit.
- [x] #225 **is closed by the restructure**, with a regression case in
      `test-habitat_partition_293.R`: the delete no longer keys on the group, so a
      row with a NULL `watershed_group_code` is addressed like any other and a
      re-run replaces it instead of appending a second copy.
- [x] File: the `F1`/`F3` residual as a sibling of #218; link's
      `cols_streams_near_river` mirror (`link/R/lnk_persist_init.R:189`) now one column
      behind — link's INSERT names columns explicitly, so nothing breaks, but the
      mirror should follow; `research/id_segment_identity.md` revised with what this
      issue settled.

## Owed at the end (reported, done after merge)

- [x] link issue for the `near_river` schema mirror.
- [x] #225 closed, or a comment saying why it survives. — fixed and tested here;
      the issue is closed at the merge.

## Validation

- [x] `devtools::test()` — **FAIL 0 | WARN 21 | SKIP 6 | PASS 2596**; the warnings
      and skips are `main`'s (fwapg migration gates, no bcfishpass schema).
- [x] `workers = 2L` through the mirai path, with two jobs over overlapping ground into
      one shared `to_habitat`: 464 rows after the outer AOI, 464 after a parallel
      re-run of the same ground, 464 after the inner AOI's 231-segment job — the
      outer's rows outside it survived. The workers load the **installed** package,
      so this needed the branch installed first; `findings.md` has why.
- [x] `lintr::lint_package()` against `origin/main`'s count in a worktree: 1598 vs
      1473. The +125 is 69 `indentation_linter` (1396 on `main`), 50
      `object_usage_linter` from an installed `fresh` **0.52.0**, and 6
      `brace_linter` that were mine and are fixed. `findings.md` has the table.
- [x] `devtools::document()`; `pkgdown::check_pkgdown()` if an export changes.
- [ ] Mutation sweep: a committed site list (`dev/mutation_sweep_sites_habitat_293.csv`)
      run with `dev/mutation_sweep.R`, each site credited only on red → green → red.
      Every guard this plan adds gets a row.
- [ ] `/code-check branch`, three rounds floor, continuing while a round finds a defect
      inside the previous round's fix — #282 had three of four rounds do exactly that.
