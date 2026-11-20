## Outcome

Integration tests now name their PostgreSQL scratch tables per run, so a suite, a mutation sweep
and a reviewer's probe can share one database without dropping each other's tables.

- **Per-run names.** Every table a live test creates is `working.t<run>_<name>`, through
  `frs_test_tbl()`. Every `frs_habitat()` label is `t<run>_<label>`, through `frs_test_label()`,
  which also names the `streams_<label>` and `barriers_<label>_gradient` tables that
  `frs_habitat()` builds itself (`frs_test_label_tbl()`). `<run>` is the R session's random
  tempdir suffix.
- **Sweep.** At the end of a run, a sweep drops what the run left under its id and names each
  table, since each one is a test that missed its cleanup.
- **Guard.** `test-test_table_names.R` is a parse-data scanner over the test, helper and setup
  files. It fails on a name two runs would share wherever a test can reach a database: the
  `working` schema in any spelling, a fixed index or constraint name, an `frs_habitat()` label
  not built with `frs_test_label()`, a watershed-group-mode `frs_habitat()` call, and a call left
  at a `to` default inside `working`.

What was learned:
- The issue's "deliberately shared fixture tables" turned out to be strings in mock blocks;
  no live test shares a fixture.
- `frs_habitat()`'s own tables can be made per run only through its label, and not at all in
  watershed-group mode. That became #310.
- The plan review and code-check rounds 1 and 3 found every gap through one mechanism: the guard
  is a lexical proxy for "a name the database resolves for both runs". The two came apart at:
  - fixed index names
  - labels passed through variables
  - bare table names in `pg_indexes` / `information_schema` lookups
  - an unqualified name resolved through `search_path`
  - a connector defined in a file the guard did not scan
  - `pg_indexes`, which lists every session's `pg_temp` tables, so even a session-local temp
    table's catalog lookup must filter on `pg_my_temp_schema()`

## Measurement

**Main alone** (98e7cf0): 2643 pass / 0 fail / 6 skip, about 15 minutes.

**This branch, two full suites at once** against one database (16:05:09–16:19:59 and
16:05:09–16:20:02 UTC, fully overlapping): 2671 pass / 0 fail / 6 skip each. 2671 is 2643 plus
the guard's 28 expectations, and the 6 skips are the same gated tests as main's. Neither run left
a relation carrying its id.

**Placeholder tables.**
- Setup: one table per name main's tests use, 192 names in all (186 created, 6 already there),
  with each table's oid recorded.
- After the two runs: 168 untouched, 24 destroyed.
- First reading: the 24 pointed at this branch.
- Discriminating probe: re-poisoning the 24 and running only this branch's `test-utils.R` and
  `test-habitat_partition_293.R` destroyed none. The 24 were dropped by an outside client running
  main's fixed-name tests in the same window. Six of them were that client's own tables, already
  present before the poisoning. The client is unattributed; a parallel #305 session was
  committing in the window, which makes it a candidate, but its records do not show it ran those
  files.
- That outside run is the #279 scenario itself, and both of this branch's runs passed through it.

**Positive control.** Main's `test-frs_extract.R` against the placeholders destroyed its three
(`test_extract`, `_both`, `_where`), so the check detects the collision it exists for.

**Guard mutations.** One per hole the plan review named, each put into a copy of a real test file:
8 of 8 red, 0 hits on the clean tree. Re-run after the round 1 fix with the same result.

**Catalog probe (round 3).** Two sessions each created a temp `probe_279_fi` with an index.
`pg_indexes WHERE tablename = …` returned 2 rows; filtered to `pg_my_temp_schema()` it returned 1.

What changed because of the numbers: the plan's acceptance grew from "two concurrent runs pass"
to the timing-free placeholder proof plus the positive control, because a rare race cannot be
shown absent by two green runs.

## Evidence

The runs were measured in one session; their numbers are in `findings.md` here (Phase 3 and
"Guard mutations"). Code-check: `review-round1.md` to `review-round4.md`, `review-verdict.md`
(ended clean at round 4, no defect inside a fix), and the plan review in `review-279.md`.

Closed by: PR for branch `279-integration-tests-name-working-tables-as` (Fixes #279)
