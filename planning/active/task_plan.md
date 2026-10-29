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
  fresh is network-agnostic, so the predicate uses `IS NOT DISTINCT FROM`. #225
  is the filed precedent: `.frs_quote_string(NA)` renders `'NA'`, which never
  matches NULL.
- **Nothing proposed here runs on CI** — `.github/workflows/` has no Postgres
  service, and `pg_temp` is a Postgres schema, so "unit" fixtures skip there too.

## Decided at the gate

- **`to_barriers` is out of scope, and gets its own issue.** Settled by the owner,
  2026-10-28, and unchanged by the review. The `to_barriers` delete keys on
  `blue_line_key` alone, and **259 FWA blue lines span more than one watershed
  group** (measured twice on this connection). That one hits the **WSG** path too.
  The projection to widen is `R/frs_break.R:350-357` (the multiclass arm
  `frs_habitat()` actually reaches).
- **Delete key: RE-OPENED.** The owner chose `(id_segment, watershed_group_code)`
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

- [ ] Re-measure `id_segment` composition (base vs derived) and real collision
      partners on the database that holds the `to_streams` target, not on a
      working table — both queries are in `review-plan.md`.
- [ ] Establish which pipeline built `fresh.streams` as it stands, so the plan
      says which table generation the fix is for.
- [ ] Put the key choice back to the owner with those numbers: pair key vs
      physical identity. If the pair key stands, the branch must state plainly
      what it does not fix.
- [ ] Correct the mechanism in the issue body and in `NEWS.md` (0.46.0's wording
      is wrong; this release is the place to correct it, since the correction is
      the finding).
- [ ] File the `frs_habitat_classify()` / `frs_near_river()` custom-AOI
      whole-group delete (below) — before Phase 1, because if it is the dominant
      loss this branch's NEWS has to be written around it.

## Phase 1: Reproduce the loss, end to end

- [ ] Integration test in `tests/testthat/test-frs_habitat.R`, following the
      file's pattern: `skip_if_not(.frs_db_available(), "DB not available")`, the
      small ltree AOI the neighbouring tests use, `working.*` tables, `on.exit()`
      cleanup.
- [ ] Assertions, in this order — the first draft asserted only survival, which a
      no-op delete also satisfies:
      1. after run 1, capture `ids1` and `n1`
      2. insert one decoy row at an id from `ids1` with `watershed_group_code = 'OTHR'`
      3. **assert the collision is live** before asserting survival: the decoy id
         is in run 2's own id set
      4. decoy survives: exactly 1 row with `'OTHR'`
      5. the job's own rows are **replaced, not duplicated**: non-`'OTHR'` count
         equals `n1` — this half is what catches the duplicate regression below
      6. `expect_setequal(ids2, ids1)` — assert the determinism premise rather
         than assume it
- [ ] Pure-string test of the SQL builder, which is the only proof that runs on
      CI at all.
- [ ] Confirm the test fails on `main` as written.

## Phase 2: One persist site instead of two

- [ ] Split the helper so one half is testable without a database:
      `.frs_persist_delete_sql(to, from, wsg_code, has_wsg)` returning a string,
      and `.frs_persist_streams(conn, to, from, wsg_code)` executing it.
- [ ] Order inside the helper must stay CREATE → `.frs_persist_columns()` →
      DELETE → INSERT, with a comment saying why: `.frs_persist_columns()`'s own
      roxygen (`R/utils.R:969-978`) exists because an INSERT used to fail *after*
      the partition DELETE had run.
- [ ] Scoped DELETE per Phase 0's decision. With `wsg_code` given, the existing
      group delete, unchanged.
- [ ] **Error, do not fall back, on column mismatch.** Four states: both tables
      carry `watershed_group_code` → scoped delete; **neither** → `id_segment`-only
      is correct (a one-group network); either one lacking it → `stop()` with a
      migration instruction. A silent fallback to a key just shown to be wrong is
      the workaround `CLAUDE.md` names as the signal to build a function instead.
- [ ] Guard the ALTER-before-DELETE hazard: when `watershed_group_code` was among
      `.frs_persist_columns()`'s added columns, pre-existing rows hold NULL, and
      `IS NOT DISTINCT FROM` will not match them against non-NULL source rows — so
      the job's own prior rows **duplicate** instead of being replaced, where
      today they are replaced. Detect and `stop()`. Same family as #225.
- [ ] Widen `.frs_persist_columns()`'s return from a pasted string to a list
      (`cols_sql`, `cols_from`, `cols_added`) — it has exactly two callers
      (`R/frs_habitat.R:507`, `:668`), and the current return cannot answer either
      the presence question or the NULL question.
- [ ] Add the missing `to_streams != paste0("working.streams_", label)` check.
      Nothing validates it today; the existing test carries the hazard as a
      comment only (`tests/testthat/test-frs_habitat.R:85`). With
      `DELETE … USING` where `to` and `from` are one relation, every row matches
      itself and the table empties.
- [ ] Replace both blocks with the helper call (`R/frs_habitat.R:503-521`,
      `:664-681`), and match `.frs_wsg_in()`'s care (`R/utils.R:645-662`) — #242's
      solution to the same shared-table problem, including its note on why the
      inner column is deliberately qualified.

## Phase 3: Prove the guard fires, and that both callers use it

- [ ] Restore the defect inside the helper, confirm Phase 1's test reddens, put
      the fix back, confirm green.
- [ ] Enumeration over the **parsed function**, not the files — a `list.files("R")`
      check cannot fire, because `devtools::test()` runs from `tests/testthat` and
      a count of zero over zero passes, and there is no `R/` at all under
      `R CMD check`. The mirai closure is lexically inside `frs_habitat`'s body,
      so one assertion covers both paths, from an installed package, with no DB:
      - no `"DELETE FROM"` in `deparse(body(frs_habitat))`
      - `"watershed_group_code"` present in the SQL builder's body
      - `"DELETE"` present in the SQL builder's body — the positive control, so a
        renamed or deleted helper fails loudly instead of passing
- [ ] `devtools::install()` then run the `workers > 1` path, or the parallel test
      fails with "object not found" rather than skipping.
- [ ] `devtools::test()` and `lintr::lint_package()` clean; `/code-check branch`,
      three rounds minimum, continuing while a round finds a defect inside the
      previous fix.

## Phase 4: Docs, repair, release

- [ ] `frs_habitat()` roxygen for `to_streams`: write the limit from the
      measurement, not from the model. Any custom AOI persisted into a table that
      already holds its own group both loses rows outside the AOI and leaves
      stale broken-segment rows behind — broader than "two custom AOIs in one
      group". `devtools::document()`.
- [ ] `data-raw/` audit for damage already in the wild: per group in
      `fresh.streams`, count FWA segments for that group absent from the table.
      State in NEWS that re-running an affected group in **WSG mode** is the
      repair, the whole-group delete being self-healing.
- [ ] File the `to_barriers` issue, citing `R/frs_break.R:350-357`.
- [ ] File the same-group `id_segment` key question, sibling of #218.
- [ ] `NEWS.md` entry — including the 0.46.0 mechanism correction, and naming
      `scripts/habitat/habitat_province.R:31-36` as what fills the shared table
      with other groups in the first place. Version bump in `DESCRIPTION` as the
      **final** commit.

## Owed at the end (reported, done after merge)

Nothing. Every sibling is filed as an issue inside Phase 0 or Phase 4.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
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
