# Task: Custom-AOI persist deletes other watershed groups' rows from to_streams (data loss, unlike the rest of the id_segment family) (#282)

## Problem

Both job paths in `frs_habitat()` delete by watershed group when `wsg` is given,
and fall back to `id_segment` when it is not:

```r
if (!is.null(wsg_code)) {
  DELETE FROM <to_streams> WHERE watershed_group_code = <wsg>
} else {
  DELETE FROM <to_streams> WHERE id_segment IN (SELECT id_segment FROM <streams_tbl>)
}
```

`R/frs_habitat.R:515` (sequential) and `:675` (mirai). In custom-AOI mode
(`wsg = NULL`) the second branch runs, `id_segment` is not unique across
watershed groups, so the DELETE matches rows of other groups and the INSERT right
after writes back only this job's. Rows are gone from a persisted table, with no
error. Unlike #242 and #277, which set a flag wrongly and are recoverable by
re-running the pass, this cannot be undone by re-running the job that caused it.

## The stated mechanism is wrong, and the plan review caught it

The issue body, the first draft of this plan, `findings.md` **and shipped
`NEWS.md` 0.46.0** all say each working table "numbers its segments independently
from `max(id_segment) + row_number()`", i.e. that numbering restarts per job.
It does not. `.frs_add_id_segment()` (`R/utils.R:571-577`) sets
`id_segment = linear_feature_id` — the FWA primary key, globally unique — and only
segments *created by breaking* get `max(id_segment) + row_number()`
(`R/frs_break.R:697-701`). There are exactly two assignment sites in `R/`, and
`git log -L` shows this one has not changed since #84.

**And yet the persisted table is the opposite.** Measured on the live DB,
2026-10-28: `fresh.streams` holds 3,802,814 rows across 98 groups with
`id_segment` running **1..n per group** and **not one row** equal to its
`linear_feature_id`; 113,305 `id_segment` values appear in more than one group,
and every one of COTR's 36,815 ids also exists elsewhere. So it was built by an
older pipeline than current `main`, and the issue's premise describes that table
correctly even though it describes the code wrongly.

The consequence is that **the right delete key depends on which table generation
is being written**, so the key decision below is re-opened rather than settled.
Queries, verdicts and the reconciliation with #218 are in `review-plan.md`.

## Context found during exploration

- **The shipped examples teach the dangerous call.** `man/frs_habitat.Rd:211-217`
  passes an ltree AOI with `to_streams = "fresh.streams"`, and the WSG examples
  at `:202-210` and `:225-233` share the same table — so mixed WSG-then-custom
  accumulation into one table is the documented default. That answers the issue's
  open question: yes, a documented workflow reaches this.
- **Two sites, one mechanism**, otherwise identical except that WSG-mode quoting
  differs: `:511` uses `.frs_quote_string(wsg_code)`, `:671` interpolates `'%s'`
  raw. The helper removes that asymmetry too.
- **Internals reach the mirai daemon**, but the closure *body* serializes by value
  while a named internal resolves in the daemon's **installed** `namespace:fresh`.
  So a `workers > 1` test of new code fails with "object not found" until
  `devtools::install()` runs — a hard error, not a skip.
- **`watershed_group_code` is `NOT NULL` with 0 nulls in FWA** (measured), but
  fresh is network-agnostic, so a NULL in that column is possible on another
  network. #225 is the filed precedent: `.frs_quote_string(NA)` renders `'NA'`,
  which never matches NULL. **Shipped as `=` plus a NULL-key guard, not as
  `IS NOT DISTINCT FROM`** — the guard covers all three keys, a predicate
  change would have covered one.
- **Nothing proposed here runs on CI** — `.github/workflows/` has no Postgres
  service, and `pg_temp` is a Postgres schema, so "unit" fixtures skip there too.

## Decided at the gate

- **`to_barriers` is out of scope, and gets its own issue.** Settled by the owner,
  2026-10-28, and unchanged by the review. The `to_barriers` delete keys on
  `blue_line_key` alone, and **259 FWA blue lines span more than one watershed
  group** (measured twice on this connection). That one hits the **WSG** path too.
  The projection to widen is `R/frs_break.R:350-357` (the multiclass arm
  `frs_habitat()` actually reaches).
- **Delete key: RE-OPENED, now measured.** Phase 0 settled the empirical half on
  2026-11-01 (`findings.md` A–F): the residual collisions on a current-code table
  are **same-group**, so the pair key does not fix the defect; a third key, the
  parent segment, is correct against both table generations and clears stale rows
  as well. The choice itself is still the owner's. History below.
- **Delete key, as it stood at the gate.** The owner chose `(id_segment, watershed_group_code)`
  on 2026-10-28, on the premise corrected above. Against a `fresh.streams`-era
  table the pair key fixes the loss and preserves a key that currently holds (0
  duplicate pairs in 3.8M rows). Against a table freshly built by current code,
  the review measured the residual collisions as **same-group** (76 of 245 derived
  ids on a 434-row AOI colliding with real same-group `linear_feature_id`s outside
  the AOI), where the pair key changes nothing and would create duplicate pairs.
  Phase 0 settles it on the table actually being written; the alternative is
  physical identity `(linear_feature_id, downstream_route_measure)`, measured as
  0 duplicates on a real working table.

## Phase 0: Settle the mechanism before writing a test against it

- [x] Re-measure `id_segment` composition (base vs derived) and real collision
      partners on the database that holds the `to_streams` target, not on a
      working table. Done 2026-11-01, `findings.md` Phase 0 A–C. The headline:
      **81 of a job's 275 derived ids name a real FWA segment and every one is
      same-group, 0 other-group** — so the pair key fixes nothing on a
      current-code table, and the re-opened decision is settled against it.
- [x] Establish which pipeline built `fresh.streams` as it stands, so the plan
      says which table generation the fix is for. Legacy: 0 of 3,802,814 rows
      have `id_segment = linear_feature_id`, and a current-code job's ids cannot
      collide with its 1..n-per-group ids at all, so **the #282 loss does not
      materialise against the legacy table** — it materialises against a target
      built by current code.
- [x] A third key the plan had not considered, found while measuring: the
      **parent segment**, `linear_feature_id IN (SELECT … FROM <from>)`. Jobs
      always hold whole FWA segments (every `.frs_resolve_aoi()` arm is a row
      predicate; no clipping anywhere in the pipeline), and 0 `linear_feature_id`
      spans a watershed group province-wide. It is the only candidate correct
      against both table generations, and the only one that clears stale
      broken-segment rows. `findings.md` Phase 0 D.
- [x] Float equality in the DELETE: **safe**, measured. Derived measures are 275
      of 275 integral (`measure_precision = 0L` → `round(…::numeric, 0)`), base
      measures are copied `double precision` to `double precision` with no cast,
      and two runs of one AOI reproduced all 464 `(lfid, drm)` pairs exactly. The
      residual risk is recomputation across *different* AOIs, which the
      parent-segment key does not have. `findings.md` Phase 0 E.
- [x] Put the key choice back to the owner with those numbers: pair key vs
      physical identity vs parent segment. Answered 2026-11-01 — **parent
      segment**, and the #293 fallout recorded in #293's body.
      (Original wording follows.) **Correction to the resume
      instruction's premise:** this does *not* decide #293. Its targets carry only
      `id_segment` and `watershed_group_code` (measured, `findings.md` Phase 0 F),
      so neither physical identity nor the parent-segment key is available there
      without widening the habitat schema — and the pair key is unsound there for
      the same same-group reason. Owed to #293's body either way.
- [x] Correct the mechanism where the claim was: `CLAUDE.md` corrected on `main`
      (`4d65b96`), pointing at the new `research/id_segment_identity.md`, which
      carries both artifacts with their queries. **`NEWS.md` 0.46.0 and the
      bodies of #231 and #282 still carry it** — filed as #295, which asks how a
      released changelog entry should be corrected.
- [x] File the `frs_habitat_classify()` / `frs_near_river()` custom-AOI
      whole-group delete — **#293**. Read it before Phase 1: if it is the
      dominant loss, this branch's NEWS has to be written around it. It is not
      the same mechanism as #231/#277/#282 (the predicate names the group
      correctly; the group *set* is too wide), so it is in none of their
      sub-issue lists.

## Phase 1: Reproduce the loss, end to end

- [x] Integration test in `tests/testthat/test-frs_habitat.R`, following the
      file's pattern: `skip_if_not(.frs_db_available(), "DB not available")`, the
      small ltree AOI the neighbouring tests use, `working.*` tables, `on.exit()`
      cleanup.
- [x] Assertions, in this order — the first draft asserted only survival, which a
      no-op delete also satisfies. One addition from Phase 0: the decoy carries a
      **different `linear_feature_id`**, because no FWA `linear_feature_id` spans
      a watershed group, so a same-lfid decoy would be legitimately deleted by a
      correctly scoped physical-identity or parent-segment key — the test would
      then pass or fail on the key rather than on the defect:
      1. after run 1, capture `ids1` and `n1`
      2. insert one decoy row at an id from `ids1` with `watershed_group_code = 'OTHR'`
      3. **assert the collision is live** before asserting survival: the decoy id
         is in run 2's own id set
      4. decoy survives: exactly 1 row with `'OTHR'`
      5. the job's own rows are **replaced, not duplicated**: non-`'OTHR'` count
         equals `n1` — this half is what catches the duplicate regression below
      6. `expect_setequal(ids2, ids1)` — assert the determinism premise rather
         than assume it
- [x] Pure-string test of the SQL builder, which is the only proof that runs on
      CI at all. Landed in Phase 2 as nine `tests/testthat/test-utils.R` cases.
      **Moved to Phase 2**: the builder it tests is Phase 2's helper,
      so it cannot be written before the key is chosen.
- [x] Confirm the test fails on `main` as written. It does, 2026-11-01: one
      failure, at the decoy-survives assertion, with the live-collision check and
      every other assertion passing. The branch carries no code change yet, so
      that run is `main`'s behaviour.

## Phase 2: One persist site instead of two

- [x] Split the helper so one half is testable without a database:
      `.frs_persist_delete_sql(to, from, wsg_code, has_wsg)` returning a string,
      and `.frs_persist_streams(conn, to, from, wsg_code)` executing it.
- [x] Order inside the helper must stay CREATE → `.frs_persist_columns()` →
      DELETE → INSERT, with a comment saying why: `.frs_persist_columns()`'s own
      roxygen (`R/utils.R:969-978`) exists because an INSERT used to fail *after*
      the partition DELETE had run.
- [x] Scoped DELETE per Phase 0's decision — the owner chose the **parent
      segment** key, 2026-11-01: `DELETE … WHERE linear_feature_id IN (SELECT
      linear_feature_id FROM <from>)`. With `wsg_code` given, the existing group
      delete, unchanged except that both paths now quote the code through
      `.frs_quote_string()` instead of one of them pasting `'%s'`.
- [x] **Error, do not fall back, on column mismatch.** Four states: both tables
      carry `watershed_group_code` → scoped delete; **neither** → `id_segment`-only
      is correct (a one-group network); either one lacking it → `stop()` with a
      migration instruction. A silent fallback to a key just shown to be wrong is
      the workaround `CLAUDE.md` names as the signal to build a function instead.
- [x] Guard the NULL-key hazard: a row whose delete key is NULL is matched by no
      partition delete, so it survives every run while the job's own rows are
      replaced beside it. `.frs_persist_columns()`'s ALTER is one way in — a
      column added now holds NULL on every pre-existing row — but not the only
      one, so the guard asks the **target** for NULL-key rows on every call
      rather than asking whether this call added the column. That proxy was
      what shipped first, and round 1 of `/code-check branch` measured it
      one-shot: the ALTER has already run when it raises, so a re-run finds
      nothing newly added, the guard goes inert, and the duplicate lands.
      Same family as #225.
- [x] Widen `.frs_persist_columns()`'s return from a pasted string to a list
      (`cols_sql`, `cols_from`, `cols_added`) — it has exactly two callers
      (`R/frs_habitat.R:507`, `:668`), and the current return cannot answer either
      the presence question or the NULL question.
- [x] Add the missing `to_streams != paste0("working.streams_", label)` check,
      as `.frs_same_relation()` inside the builder, so it is one of the
      CI-runnable cases.
      Nothing validates it today; the existing test carries the hazard as a
      comment only (`tests/testthat/test-frs_habitat.R:85`). With
      `DELETE … USING` where `to` and `from` are one relation, every row matches
      itself and the table empties.
- [x] Replace both blocks with the helper call (`R/frs_habitat.R:503-521`,
      `:664-681`), and match `.frs_wsg_in()`'s care (`R/utils.R:645-662`) — #242's
      solution to the same shared-table problem, including its note on why the
      inner column is deliberately qualified.

## Phase 3: Prove the guard fires, and that both callers use it

- [x] Restore the defect inside the helper, confirm Phase 1's test reddens, put
      the fix back, confirm green. Done mechanically rather than by hand, with
      `dev/mutation_sweep.R` over 10 sites: baseline 0 red / 0 skip, each site
      credited only on red -> green -> red. **0 of 10 uncaught**; the defect
      site reddens four tests, including Phase 1's. Table in `findings.md`.
- [x] Enumeration over the **parsed function**, not the files — a `list.files("R")`
      check cannot fire, because `devtools::test()` runs from `tests/testthat` and
      a count of zero over zero passes, and there is no `R/` at all under
      `R CMD check`. The mirai closure is lexically inside `frs_habitat`'s body,
      so one assertion covers both paths, from an installed package, with no DB:
      - no streams partition delete in `deparse(body(frs_habitat))`, and every
        `DELETE FROM` left in it is the `to_barriers` `blue_line_key` one —
        #294's scope, deliberately untouched. Pinned by count, so a new
        unscoped delete cannot be added without reddening the test. (Adapted
        from the plan's "no `DELETE FROM` at all", which `to_barriers`
        staying makes unachievable.)
      - `.frs_persist_streams(` appears exactly twice, one per path
      - `"watershed_group_code"` present in the SQL builder's body
      - `"DELETE"` present in the SQL builder's body — the positive control, so a
        renamed or deleted helper fails loudly instead of passing
- [x] `devtools::install()` run, which also cleared the two
      `object_usage_linter` warnings for `.frs_persist_streams` — the stale
      installed package, not a defect (`exists()` against the installed 0.51.0
      was `FALSE`). `workers > 1` run against the installed branch, 2026-11-01:
      the #282 scenario through `R/frs_habitat.R:668` passes all six assertions
      (no test in the suite exercises `workers`, and a `load_all()` run could
      not, since the daemon resolves internals in the installed namespace).
- [x] `devtools::test()` and `lintr::lint_package()` clean; `/code-check branch`,
      three rounds minimum, continuing while a round finds a defect inside the
      previous fix. Four rounds ran; three of them found a defect inside the
      previous round's fix, so the loop closed on round 4's enumeration and the
      16-site mutation sweep that measures it (0 uncaught), not on a quiet round.
      Full suite against the reinstalled branch, 2026-11-01: **FAIL 0 | WARN 21 |
      SKIP 6 | PASS 2542** (21 warnings and 6 skips are `main`'s, unchanged).
      `workers = 2L` re-run after the helper's four revisions: PASS, all six
      assertions. `lintr::lint_package()` 1471 on the branch against 1400 on
      `origin/main`, measured in a worktree: +70 `indentation_linter` on the
      added lines, which this package carries 1400 of before the branch, and one
      `brace_linter` that was mine and is fixed. 0 of either on the changed files
      that `origin/main` does not already have in kind.

## Phase 4: Docs, repair, release

- [x] `frs_habitat()` roxygen for `to_streams`: write the limit from the
      measurement, not from the model. Any custom AOI persisted into a table that
      already holds its own group both loses rows outside the AOI and leaves
      stale broken-segment rows behind — broader than "two custom AOIs in one
      group". `devtools::document()`.
- [x] `data-raw/audit_persist_282.R`. Run: 98 groups, 3 with a shortfall, 34
      segments, and all 34 are `edge_type` 6010 construction-line connectors
      with their blue lines present — a filter's signature, not loss. Agrees
      with Phase 0, which says the loss cannot have happened on this table.
      Original wording: per group in
      `fresh.streams`, count FWA segments for that group absent from the table.
      State in NEWS that re-running an affected group in **WSG mode** is the
      repair, the whole-group delete being self-healing.
- [x] File the `to_barriers` issue — **#294**, citing `R/frs_break.R:350-358`
      (the multiclass arm) and the 259 spanning blue lines.
- [x] File the same-group `id_segment` key question, sibling of #218 — moot
      for `to_streams`, which no longer keys on `id_segment` at all. Where it
      does arise is #293, and it is option (c) in that body: filed, not dropped,
      and not duplicated into a new issue.
- [x] `NEWS.md` entry, as **0.53.0**: `origin/main` released 0.52.0 under the
      branch, so the number moved and the roxygen's "before 0.52.0" moved with
      it. #295's question answered by leaving the released 0.46.0 entry as
      written — a changelog is history — and carrying the correction in this
      entry, pointing at `research/id_segment_identity.md`; #295 stays open for
      #231's body. `scripts/habitat/habitat_province.R:31-32` is confirmed as
      what fills the shared table (all WSGs into `fresh.streams`) but is not
      named in NEWS: the entry describes the package's own inputs, and a path
      into a run script is not one of them.
- [ ] Version bump in `DESCRIPTION` to 0.53.0 as the **final** commit.

## Owed at the end (reported, done after merge)

Nothing. Every sibling is filed as an issue inside Phase 0 or Phase 4.

## Validation

- [x] Tests pass — FAIL 0 | PASS 2542, plus the `workers = 2L` path
- [x] `/code-check` clean (once over the branch with `/code-check branch`) —
      four rounds, closed by enumeration
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

**How each change is proved:**

- The data loss: Phase 1's integration test, run against `main` (red) and the fix
  (green), with the collision asserted live before survival is asserted, and the
  non-decoy count pinned to a number. End to end through `frs_habitat()`, so it
  proves the caller and not just the helper.
- On CI, where no database exists: the pure-string test of the SQL builder. It is
  the only automated proof, which is why Phase 2 splits the helper.
- The fix's guard: Phase 3's restore-the-defect run, reported as a mutation
  result rather than a claim.
- Both call sites: three `deparse(body())` assertions with a positive control.
- Blast radius is **not** proved by the synthetic decoy — a decoy at a hand-picked
  id shows the delete is scoped and measures nothing about rows at risk. The
  blast-radius numbers come from Phase 0's queries against the real target table.
- Every measured figure quoted in `NEWS.md` is re-derived from the DB at the time
  of writing, with the query recorded in `findings.md`.
