# fresh#293 — code-check round 4

Reviewed at `c4edd3d` (branch `293-custom-aoi-jobs-delete-whole-watershed-g`), the round-3
fix commit. The working tree was **clean** at review start and at review end
(`git status --porcelain` empty, both times), one worktree besides this one
(`/Users/airvine/Projects/repo/fresh-cloud`, detached at `0e9c46f`, untouched).
**Nothing in the repository was modified by this review apart from this file**; the one
script I ran went to the session scratchpad. No test suite, no `frs_habitat*` call, no
write to the database. Line numbers are against `c4edd3d`.

Round 3 found a defect inside a round-2 fix, so this round's target was a defect inside
round 3's own fixes. There is one, and it is larger than a defect: **two of round 3's three
fixes are not in the tree at all, and the branch's record says they are.**

## Checklist read

- `indexes.txt` — in full (354 `###` headings across the five index blocks). It is the same
  text this repo's `CLAUDE.md` loads into the session, confirmed by heading count and by
  spot-reading each block's boundaries (`code-check-infra` at :2, `-r` at :131, `-shell` at
  :481, `-spatial` at :696, `code-check.md` at :983 with `## Mechanisms` at :988).
- `ck/code-check-infra.md` — **in full** (all 435 lines: Cloud-Init, OpenTofu/Terraform,
  DigitalOcean, Docker/Postgres, Tailscale, every `<!-- evidence -->` block). Applicable and
  checked: *"An `IF NOT EXISTS` that finds nothing to do still waits for its lock"* (the
  brief's item 3 — see Notes, the DDL is not in the tree), *"Two-statement DELETE/INSERT into
  a persist table is not atomic"* (the branch's own citation, satisfied), *"Joining on a
  per-tenant key … is cartesian"*, *"`pkill` does NOT cancel its Postgres query"*,
  *"Set `statement_timeout` + `lock_timeout` on long DB ops"*.
- `ck/code-check.md` — `## Mechanisms` prose read in full (lines 38–1255), all fourteen H3s.
  Opened in full from `## Rules that stand alone`: "Documentation Staleness", "Do not edit
  files a long test run is reading", "An assertion that matches an interpolated value cannot
  see the claim around it", "Test the cold/create path of idempotent code". Security and
  Spreadsheets/PDFs from the index only — no secret, no provisioning, no spreadsheet or PDF
  in this diff.
- `ck/code-check-r.md` — opened the sections the diff's shapes name: `on.exit()`,
  `tryCatch()` nesting, `tryCatch(warning =)` discarding the value, `$` partial matching,
  `[[` on a named atomic vector, zero-length / `paste()`, `ifelse()` with an all-NA test,
  "A `function(...)` mock hides arguments the real callee no longer accepts",
  `local_mocked_bindings(.package =)`, `expect_message(regexp = "...$")`, testthat counting
  an error under `error`, "A `pkg::` call in a test…", "Postgres row order is never fixed…",
  "`sprintf(\"%g\", x)` writes `Inf` and `NA`…", "A database driver's value is not a base R
  type", "An `information_schema` lookup by the literal table name…", "`R CMD build` ships
  every top-level directory…". The rest from the index (arrow, duckdb, ggplot2, climr,
  reticulate, earthdatalogin, pagedown — none in this diff).
- `ck/code-check-shell.md` — index only; the diff contains no shell.
- `ck/code-check-spatial.md` — index only; the diff touches no terra/sf/GDAL/bcdata call.

## Findings

- **[severity: bug]** `R/frs_habitat_predicates.R:166`, `R/utils.R:355`, `R/utils.R:590` —
  **round 3's second fix was never written to `R/`. The record says it was.**
  `planning/active/findings.md:411` and `planning/active/review-round3.md` state *"the
  argument is now **required** when `near_river_table` is given, with a message naming both
  answers. 14 test call sites and 4 internal ones say which they mean"*, and the commit
  subject is *"the mechanism, an enumeration, and three fixes"*. The call sites were updated.
  The function was not:

  ```r
  frs_habitat_predicates <- function(sp_params, model = "cw",
                                     near_river_table = NULL,
                                     near_river_lfid = FALSE) {   # :164-166
  .frs_rule_to_sql  <- function(rule, csv_thresholds = NULL,
                                near_river_table = NULL,
                                near_river_lfid = FALSE) {        # utils.R:353-355
  .frs_rules_to_sql <- function(rules, csv_thresholds = NULL,
                                near_river_table = NULL,
                                near_river_lfid = FALSE) {        # utils.R:588-590
  ```

  `git diff 906f308 HEAD --stat` lists neither file. There is no `missing()` check, no
  `isTRUE()` coercion, and no error message anywhere in the package mentioning
  `near_river_lfid` (`grep -rn "isTRUE(near_river_lfid)\|missing(near_river_lfid)\|
  near_river_lfid must\|near_river_lfid is required" R/ tests/ man/ NEWS.md` → nothing).
  `man/frs_habitat_predicates.Rd:11` still renders `near_river_lfid = FALSE`, the roxygen at
  `:117-126` still says *"Default `FALSE`, which builds exactly the predicate fresh 0.53.0
  built"*, and `NEWS.md:16` still publishes *"takes `near_river_lfid`, default `FALSE`"*. The
  parent's own snapshot of the changed files (`files.txt:356`, `:591`, `:3376`) carries the
  `FALSE` defaults too, so this is not a stale checkout on my side.

  So the defect round 3 raised is live and unfixed: from 0.54.0 the narrowed delete is
  automatic, the shared `near_river` table begins holding two jobs' rows in one group, and any
  caller re-deriving the predicate without passing the flag gets 0.53.0's short-key `EXISTS`
  and can pass `near_river` on a distance measured for a different segment. Round 3 named the
  real caller (link's `lnk_habitat_validate.R`).

  **The record being wrong is the worse half.** Round 3's termination argument is an
  enumeration, and the next round will read `findings.md`'s resolution column rather than
  re-derive it — which is exactly how this class survives. Either land the guard or revert the
  claim; do not leave a fix recorded as made.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness"

- **[severity: fragile]** `tests/testthat/test-near_river_inherit.R:299-300`,
  `tests/testthat/test-near_river_rules.R:226`, `data-raw/predicates_fixture_0410.R:28` — **the
  mechanical substitution that was supposed to accompany that guard missed three call sites**,
  which is also the proof the guard was never run against the suite: had it landed, two of
  these would be red.

  Enumerated by parsing — every `R/`, `tests/testthat/` and `data-raw/` file through
  `parse()`, walking every call to `frs_habitat_predicates`, `.frs_rule_to_sql`,
  `.frs_rules_to_sql` and `.frs_near_river_sql`, and recording whether each passes
  `near_river_table` and whether it passes the lfid argument. 21 sites pass both; three pass
  the table and not the flag:

  | site | call |
  |---|---|
  | `test-near_river_inherit.R:299-300` | `frs_habitat_predicates(sp_of(params, sp), model = model, near_river_table = "w.streams_near_river")` — the 0.41.0 byte-identity test |
  | `test-near_river_rules.R:226` | `.frs_rule_to_sql(rule, near_river_table = "x; DROP")` — the identifier-injection `expect_error`, whose matched message would change if a new guard fired first |
  | `data-raw/predicates_fixture_0410.R:28` | `frs_habitat_predicates(sp_params, model = model, near_river_table = "w.streams_near_river")` |

  The `data-raw/` one **must stay as it is**: the script `pkgload::load_all()`s a worktree of
  `v0.41.0` (`:13`), which has no `near_river_lfid` formal at all, so adding the argument
  breaks the fixture generator. Its consumer at `test-near_river_inherit.R:300` must therefore
  compile at `lfid = FALSE` to match `predicates.rds`, which means the guard has to be
  satisfiable by an explicit `FALSE` there — which it is, but nobody has written it. Whoever
  lands the guard needs all three in the same commit.
  - **Rule:** code-check.md "Restore the bug and prove the guard fires"

- **[severity: fragile]** `R/frs_near_river.R:206-212` — **the comment still states the
  mechanism round 3 measured false, and the record says it was corrected.**
  `findings.md`'s round-3 resolution column reads *"comment corrected to the measured
  mechanism: rolling back first **ends** the transaction, so the following `DROP` raises
  nothing"*. The committed comment is unchanged from `ae7f621`:

  ```r
  # after = FALSE, so this runs BEFORE the walk table's DROP registered
  # above. Handlers run in registration order, and a DROP issued inside an
  # aborted transaction raises "current transaction is aborted", which
  # propagates out of on.exit and leaves the rollback unrun and the
  # connection stuck for every later statement (measured: it broke four
  # tests two files away). Rolling back first drops the temp table anyway,
  # so the DROP is then a no-op.
  ```

  Round 3 measured on R 4.5.2 that both handlers run in **both** orders — an error in one
  `on.exit` expression does not skip the others — so "leaves the rollback unrun and the
  connection stuck for every later statement" is false. What the old order lost was the error
  *message*: 25P02 replaced the real cause, which is what broke the four tests.

  Why it matters rather than being a wording nit: the sentence is the only written account of
  why the ordering is load-bearing, and it says the wrong thing in the direction that invites
  a wrong change. A reader told the rollback can be skipped will reach for a second guard
  (re-registering, a flag, a `tryCatch` round the DROP) against a failure that cannot happen,
  and will not see the one that can — a replaced diagnosis. It also asserts a connection-state
  and potential-data-loss failure where none exists, which is the kind of claim that gets
  copied into an issue body.
  - **Rule:** code-check.md "Documentation Staleness"

- **[severity: fragile]** `R/frs_near_river.R:189-214` — **`after = FALSE` closes the branch
  where fresh opened the transaction and leaves the branch where the caller did.** The comment
  three lines above it (`:189-190`) states that path as supported: *"dbBegin() refuses a nested
  transaction, and a caller who already holds one has made the pair atomic with respect to
  their own commit."* On that path `began` is `FALSE`, so the `if (began)` block at `:204` never
  runs and **no rollback handler is registered at all**. The only handler is the walk-table
  cleanup registered at `:150-151`:

  ```r
  on.exit(.frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", walk_tbl)),
          add = TRUE)                                    # :150-151
  ```

  A mid-walk failure then leaves the caller's transaction aborted, the `DROP TABLE IF EXISTS`
  raises 25P02, and the body's error is replaced — the exact failure the fix was for, reached
  through the other branch. And the comment's closing sentence, *"Rolling back first drops the
  temp table anyway, so the DROP is then a no-op"*, is true only on the branch that has a
  rollback.

  Round 3's own stated remedy covered both: *"register the walk-table drop after the
  transaction block, or to wrap it in `try()`."* The reorder covers one. `try()` on the DROP
  is two characters of change and is order-independent, so it does not depend on which branch
  ran.

  Reachability, measured by reading: `frs_habitat_classify()` calls `frs_near_river()` at
  `R/frs_habitat_classify.R:297`, well before its own `DBI::dbBegin()` at `:403`, so nothing
  inside fresh takes the nested branch. It is an external-caller path only, which is why this
  is fragile and not a bug. The new sweep row (`dev/mutation_sweep_sites_habitat_293.csv`,
  `"293 rollback runs before the walk DROP"`) mutates `after = FALSE` away and so exercises
  the `began == TRUE` branch only; nothing in the list reaches the nested one.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** `planning/active/findings.md:159` and
  `research/id_segment_identity.md:125` — **round 3's re-measurement landed on two of the four
  copies of the counts.** The same commit that rewrote the table at `findings.md:144-145` to
  `221 / 0` and `114 / 20` left the paragraph fifteen lines below it saying *"The **realised**
  exposure is `near_river`: **21** tables are shared across 2 to 125 groups"* — a direct
  contradiction of the table it sits under, in the same file. And the durable record,
  `research/id_segment_identity.md:125`, still reads *"(measured: **199** habitat tables and
  **98** `near_river` tables on the shared instance, **0** with `linear_feature_id`)"* under a
  header dated `**Verified:** 2026-11-02` — the date of the re-measurement that produced
  221/114. The committed CSV (`data-raw/logs/habitat_293/summary.csv`) says 221/114/20.

  This is the mechanism round 3 itself named ("N restatements of one fact"), one axis over:
  its Axis 6 enumerated the prose restatements of the *read key* and did not enumerate the
  restatements of the *counts* the same commit was changing. The research file is the copy that
  outlives the branch, and `planning.md` makes it the one to grep when a number moves.

  The *published* numbers are fine: `NEWS.md:10` (221, 0, 114, 20, 2 to 125) and `:11`
  (50,808 / 69,956 / 5 groups / 19,148 / 0.38) all re-derive from `summary.csv` and
  `ratio.csv`, which I checked value by value. Only the two restatements are stale.
  - **Rule:** code-check.md "Documentation Staleness"

## Verified sound, so recorded rather than flagged

- **The new `@param wsg_code` paragraph is true** (`R/frs_near_river.R:110-114`,
  `man/frs_near_river.Rd:64-68`). Traced it: a non-`NULL` `wsg_code` makes
  `.frs_persist_delete_key()` return `"watershed_group_code"` unconditionally (`utils.R:1329`,
  before any `linear_feature_id` branch), and `.frs_persist_delete_sql()`'s
  `watershed_group_code` arm returns `DELETE FROM %s WHERE watershed_group_code = %s` and
  **drops `extra_subset` entirely** (`utils.R:1611-1615`). So a whole-group replace does remove
  every `(measure, threshold, distance_max)` the group holds, and the `@examples` at `:126-139`
  do accumulate two measures (`discharge`, then `channel_width`) into one `working_bulk.near_river`
  — which is what makes the warning load-bearing. Both halves check out.
- **`tgt$lfid` can never be NULL or NA.** `.frs_habitat_target()` returns
  `lfid = lfid && "linear_feature_id" %in% cols_to` (`utils.R:124`), where `lfid` is
  `"linear_feature_id" %in% cols_from` — `%in%` never returns NA, and `&&` on two logical
  scalars never does either. `$lfid` is an exact name on the returned list, with no sibling it
  could partial-match (`key`, `lfid`, `cols_to`, `cols_from`), so `code-check-r.md`'s `$`
  partial-matching trap does not apply. `.frs_habitat_target()` has exactly one caller
  (`frs_habitat_classify.R:284`) and no test mocks it, so there is no path that supplies a list
  without `lfid`.
- **The near_river table's `linear_feature_id` cannot disagree with `tgt$lfid`.**
  `.frs_near_river_check_shape()` raises when `lfid != ("linear_feature_id" %in% have)` on the
  target (`frs_near_river.R:436-443`), so the walk's table carries the column exactly when the
  streams table does — which is also what `tgt$lfid` reduces to. The predicate at
  `utils.R:565-570` therefore never names a column the table lacks.
- **The `.frs_group_required` mock added to `test-frs_habitat_classify.R:547` matches the real
  formals** `(conn, table, lfid)` exactly (`utils.R:1485`), so `code-check-r.md`'s
  "A `function(...)` mock hides arguments the real callee no longer accepts" does not bite —
  the mock is stricter than `...`, which is the right direction. It is also necessary: without
  it the real `.frs_group_required()` reaches `DBI::dbGetQuery()` on the string `"mock"` through
  its own frame, which `mockery::stub(frs_habitat_classify, …)` cannot patch, and the error
  would land before the per-species count SQL the test asserts on. That the suite must have
  been run to find this is part of why finding 1 stands out.
- **`groups_min_shared`'s empty case is correct** (`data-raw/audit_habitat_293.R:190`):
  `if (nrow(sh) == 0) NA_integer_ else min(sh$n_groups)`, and the `habitat` row in the committed
  `summary.csv` is `NA` as it should be. `n_groups` comes from a `count(distinct …)` so it is
  never NA, and the int/double mix across the two rows is resolved by `rbind.data.frame`'s
  coercion rather than silently dropped.
- **The 21 substituted call sites are all on functions that accept the argument**
  (`frs_habitat_predicates`, `.frs_rule_to_sql`, `.frs_rules_to_sql`) and all pass `FALSE`,
  which is the current default, so no assertion changed — confirmed by parse rather than by
  reading the diff. The `expect_identical(a, b)` pair at `test-near_river_rules.R:239-241`
  still compares two `FALSE` compilations, as intended.
- **Index-name collision, for the record** (the brief's concern on item 3): the `_lfid_idx`
  builders derive the name from the table's last dot-segment (`.frs_index_working()`
  `utils.R:732`, `.frs_near_river_table()` `frs_near_river.R:474-476`). Postgres puts an index
  in its table's schema, so `fresh.streams_habitat` and `other.streams_habitat` get
  same-named indexes in different schemas and do not collide, and two distinct tables in one
  schema cannot produce the same name. Nothing to fix.

## Notes — three of the brief's six items are not in `c4edd3d`

The brief for this round describes six changes. Three are in the tree (the `@param wsg_code`
paragraph, `groups_min_shared`, the test substitution), one is in the tree but not as described
(the `on.exit` comment, finding 3), and **two are absent**:

| brief item | state at `c4edd3d` |
|---|---|
| 2. `near_river_lfid` required, with `isTRUE()` after the guard | **absent** — finding 1 |
| 3. `CREATE INDEX IF NOT EXISTS <name>_lfid_idx` in `.frs_habitat_target()` | **absent** — `grep -rn lfid_idx R/` returns only `utils.R:732` (`.frs_index_working()`, generic, all tables) and `frs_near_river.R:476` (`.frs_near_river_table()`). `.frs_habitat_target()` (`utils.R:94-127`) runs `CREATE TABLE IF NOT EXISTS`, then `ALTER TABLE … ADD COLUMN IF NOT EXISTS`, then the key chooser and the null-key guard, and no `CREATE INDEX`. `frs_habitat_classify.R:536`'s `.frs_index_working(conn, to)` still runs after the commit, so the first migrated run's delete is still a sequential scan — which round 3's own Notes called performance-only and self-correcting, so its absence is **not** a defect |

Item 3's absence also means the locking question the brief raises does not arise on this
branch: no new DDL was added inside or beside the transaction, and the two existing
`IF NOT EXISTS` statements in `.frs_habitat_target()` are pre-existing and autocommitted
(the `dbBegin()` is at `frs_habitat_classify.R:403`, long after `:284`). The
`code-check-infra.md` rule that applies — *"An `IF NOT EXISTS` that finds nothing to do still
waits for its lock"* — is unchanged in its reach by this diff.
