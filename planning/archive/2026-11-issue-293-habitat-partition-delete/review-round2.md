# fresh#293 — code-check round 2

Reviewed at `770fba5` (branch `293-custom-aoi-jobs-delete-whole-watershed-g`), the round-1
fix commit. Working tree clean at review start; **nothing in the repository was modified by
this review apart from this file** (scratch scripts went to the session scratchpad).
Line numbers are against the live tree at `770fba5`.

## Checklist read

- `indexes.txt` — in full. The five indexes are carried verbatim in this repo's
  `CLAUDE.md`, which loads into the session; I additionally verified the file's structure
  against it (354 `###` headings across the 5 index blocks, same headings).
- `ck/code-check-infra.md` — **in full** (all 434 lines: Cloud-Init, OpenTofu/Terraform,
  DigitalOcean, Docker/Postgres, Tailscale, including every `<!-- evidence -->` block).
- `ck/code-check.md` — `## Mechanisms` header plus the full prose of the H3s this diff can
  instance: "A guard that fails toward pass", "A fixture that cannot reach the failure
  mode", "A proxy is not the property", "Verification that reads its own output", "A
  guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that
  share a harness", "Restore the bug and prove the guard fires", "A wrapper's exit is not
  the work", "Zero-length, empty, and unset are three different things", "The probe is
  broken before the world is", "Written data outlives the fix", "Serialization loses
  meaning silently", "One fact derived twice". Not opened in full: "A shared working tree,
  and what generators leave in it". From `## Rules that stand alone` I opened
  "Documentation Staleness", "An ordered dispatch…", "An assertion that matches an
  interpolated value…", "A pluralisation marker…", "Do not edit files a long test run is
  reading"; the remaining ~24 headings in that section plus all of Security and
  Spreadsheets/PDFs I read from the index only (no shell provisioning, no secrets, no
  spreadsheet or PDF in this diff).
- `ck/code-check-r.md` — opened in full: "Cross-function consistency for label/string
  normalization", "An `information_schema` lookup by the literal table name misses what
  Postgres resolves", "Postgres row order is never fixed…", "`sprintf(\"%g\", x)` writes
  `Inf` and `NA`…", "Verify a float-formatting fix in its consumer…", "A database driver's
  value is not a base R type", "A value compared as `::text` in SQL has PostgreSQL's
  spelling", "Zero-length / `paste()` with a zero-length argument", "`[[` on a named ATOMIC
  vector", "`$` on a list partial-matches", "`ifelse()` with an all-NA test",
  "`tryCatch(warning = )` DISCARDS the value", "`tryCatch()` nests its handlers",
  "`deparse(body(f))` excludes formal defaults", "`sort()` and `order()` collate by
  `LC_COLLATE`", "A `function(...)` mock hides arguments", "`expect_message(regexp =
  \"...$\")`", "`local_mocked_bindings(.package = )`", "`expect_gt()` and friends take no
  `info`", "A `pkg::` call in a test…", "`R CMD build` ships every top-level directory…",
  "testthat's failure snapshots…". ~70 further headings read from the index only (arrow,
  duckdb, ggplot2, climr, reticulate, readBin, pagedown, earthdatalogin, etc. — none
  present in this diff).
- `ck/code-check-shell.md` — index only; the diff contains no shell.
- `ck/code-check-spatial.md` — index only, scanned for applicable headings. Two were
  checked against the diff and do not apply (`sf::st_read()` promote_to_multi; FWA
  `upstream_route_measure`); 0 opened in full. The diff touches no terra/sf/GDAL/bcdata
  call.

## Mechanical checks run

- **Every `sprintf()` in the eight changed `R/` files, parsed (not grepped), conversion
  specs counted against positional arguments: 0 mismatches.** Argument *order* for each
  changed template was then read by hand: the three newly converted
  `.frs_connected_waterbody()` joins (`origins_sql`, `rearing_segs`, `spawn_upstream`),
  `.frs_bucket_connected()`'s `hab_join` + subtractive UPDATE, `.frs_rearing_distance()`
  (`key`, `key_r`), `frs_order_child()`, `frs_habitat_overlay()`, all four `frs_cluster`
  helpers (upstream, downstream, both phases 1-3 and the write-back), the classify INSERT
  and the near_river INSERT — **all correct**, and every CTE / temp table a
  `.frs_key_match()` predicate pins against does project the columns it names
  (`clustering`/`tmp_clusters` gain `s.linear_feature_id` via `lfid_col`; `s` in
  `frs_order_child` is `SELECT *`; `st`/`s2`/`s3`/`r` are the streams table).
- **Replicated the new enumeration test's scan over `R/` by parsing all 172 top-level
  functions and deparsing each**: found exactly `.frs_bucket_connected = 2`,
  `.frs_connected_waterbody = 2`, `.frs_near_river_sql = 1`, `frs_habitat_classify = 1` —
  **identical to the allowlist**, and each of the four is genuinely safe (checked each
  site: `frs_habitat.R:1449`/`:1474` join `table` to a trace temp table built from
  `table`; `:1889` joins two CTEs of one statement; `:1921`'s `h` is already pinned to a
  `table` row by `key`; `utils.R:564` carries the optional `lfid` term). The test **can**
  fail — an empty `found` is `integer(0)` with no names and `expect_identical` against the
  4-name `allowed` goes red — and it uses `deparse(f)`, not `deparse(body(f))`, so formal
  defaults are in scope.
- **Number formatting on the new pair predicate, traced end to end**:
  `.frs_near_river_pairs_in()` writes `threshold` through `.frs_sql_num()`; the stored
  `threshold` comes from `w.threshold` ← `q.threshold` ← `.frs_near_river_values()`, also
  `.frs_sql_num()`; `distance_max` is `.frs_sql_num(d)::double precision` on write and
  `.frs_sql_num(d)` in the predicate; `measure` is `.frs_quote_string()` on both sides.
  **Each equality compares one literal with itself — the roxygen claim holds.**

## Findings

- **[severity: fragile]** `R/frs_near_river.R:326-334` (used at `:180-182`) —
  `.frs_near_river_pairs_in()` returns **`NULL`** for an empty pair list, and
  `.frs_persist_delete_sql()` reads `NULL` as *"do not narrow"*, not as *"narrow to
  nothing"*. So the degenerate input widens the delete to every pair on the job's ground
  while the loop below writes none of them back:

  ```r
  .frs_near_river_pairs_in <- function(measure, threshold, distance_max) {
    if (length(threshold) == 0) return(NULL)          # <- reads as "every pair"
  ```

  ```r
  #' @return Character SQL, or `NULL` when there are no pairs.
  ```

  `.frs_persist_delete_sql()`'s own contract is the other meaning
  (`R/utils.R:1540-1542`: *"`extra_subset` — Character or `NULL`. A further predicate to
  AND into a **subset** delete"*), and at `R/utils.R:1573-1575` `NULL` emits no predicate
  at all, leaving `DELETE FROM <to> WHERE linear_feature_id IN (SELECT linear_feature_id
  FROM <table>)` — the whole of this issue, in the `near_river` table, produced by the
  function added to prevent it.

  **This is round 1's finding 5 one axis over.** There the same R idiom
  (`extra_subset = if (length(sp_classify) > 0) {...}` → `NULL`) was the bug, and the fix
  chose to **skip the delete** (`R/frs_habitat_classify.R:420`,
  `if (overwrite && length(sp_classify) > 0)`). The near_river fix, written in the same
  commit against the same hazard, instead hands the same `NULL` to the same reader. The two
  coupled stores now have opposite degenerate-input policies.

  **Reachability, stated precisely:** zero today. `frs_near_river()` calls
  `.frs_near_river_check()` first, whose `ok_num()` requires `length(threshold) > 0`
  (`R/frs_near_river.R:245-250`), and `frs_habitat_classify()` guards separately on
  `nrow(near_specs) > 0` (`:265-266`). So this is latent, not live — but the protection
  sits two frames away in a validator whose stated job is numeric *validity*, the helper's
  own documented return value is the fail-open, and the sibling in the same commit chose
  the safe branch. Returning `"FALSE"` (delete nothing) or raising makes the two symmetric.
  - **Rule:** code-check.md "Zero-length, empty, and unset are three different things" ;
    code-check.md "A fix lands in one of two callers that share a harness"

- **[severity: bug]** `R/frs_near_river.R:180-221` — `frs_near_river()`'s DELETE and its
  per-pair INSERTs are still **not one transaction**, while the branch gave exactly that
  treatment to the two sibling writers and newly narrowed this one's delete.

  `.frs_null_key_guard()`'s roxygen names the set itself (`R/utils.R:1369-1371`): *"three
  writers need it — `.frs_persist_streams()`, `frs_habitat_classify()` and
  `frs_near_river()` (fresh#293)"*. Two of the three wrap the pair:
  `.frs_persist_streams()` at `R/utils.R:1668-1691` (0.53.0) and
  `frs_habitat_classify()` at `R/frs_habitat_classify.R:393-522` (added by this branch,
  citing code-check-infra.md by name). `frs_near_river()` has no `dbBegin` anywhere —
  `grep -rn "dbBegin" R/` returns only those two and `frs_migration_trial.R`.

  The harm is not hypothetical and the branch states it itself, in `NEWS.md`: *"A deleted
  group there is rebuilt by the next run of that group, but until then a classify over
  another group reads a table missing those rows, so every `near_river` predicate silently
  fails and the habitat written is under-classified."* The walk is the expensive statement
  in the whole pipeline (`.frs_near_river_walk_sql()` — a `FWA_Downstream` predicate join
  with `ST_DWithin` prefiltering, window frames and `ST_Intersection` against four polygon
  tables), so it is the statement most likely to meet the `statement_timeout` CLAUDE.md
  prescribes, a cancellation, or a dropped connection. With `length(threshold) > 1` — which
  is the normal case, one pair per rule — a failure in walk *i* leaves pairs *i..n* deleted
  and not written back, and classify then proceeds to write habitat rows whose `near_river`
  predicates read FALSE for them. The same commit's comment at `:176-179` explicitly draws
  the sibling parallel (*"as the habitat delete is scoped to the species it classifies"*),
  so the asymmetry is in the atomicity, not in the reasoning.

  Pre-existing on `origin/main` in form; what this branch changed is that it narrowed this
  delete, added this guard, and fixed the identical atomicity hole in the sibling, leaving
  one of a named set of three untreated.
  - **Rule:** code-check-infra.md "Two-statement DELETE/INSERT into a persist table is not
    atomic" ; code-check.md "A fix lands in one of two callers that share a harness"

- **[severity: fragile]** `R/frs_near_river.R:193-210` vs `R/utils.R:563-573` and
  `R/frs_near_river.R:306-310` — round 1's fix 6 dropped the group equality from the
  **writer** so a NULL-`watershed_group_code` row is carried into `near_river`, and the two
  things that then read or address that row were not changed, so the stated purpose is not
  achieved and a new refusal is created.

  The fix and its justification:

  ```r
  # Not also on `watershed_group_code`: that column is nullable on a network that is not
  # the FWA, and an equality join on it would silently drop a NULL-group row from the
  # insert rather than carrying its parent.
  ... JOIN %s s ON s.id_segment = w.origin_id
  ```

  1. **The reader still cannot see it.** `.frs_near_river_sql()` is unchanged on this
     column (`R/utils.R:565`, `"AND n.watershed_group_code = s.watershed_group_code "` —
     confirmed untouched in the branch diff), so for a NULL-group segment the `EXISTS`
     is UNKNOWN and the predicate reads FALSE exactly as before. Round 1's stated harm —
     *"every `near_river` predicate for it reads FALSE — under-classified habitat with no
     error"* — is unchanged; the row is now written and still unreadable. `test-habitat_partition_293.R:48-52`
     pins that group term in place for both `lfid` arms, so the half-fix is now asserted.
  2. **The new guard refuses the table once such a row exists.** For a whole-group run
     (`wsg_code` non-NULL) `.frs_persist_delete_key()` returns `"watershed_group_code"`
     (`R/utils.R:1314-1329`), so the guard moved into `.frs_near_river_check()` by fix 4
     counts `watershed_group_code IS NULL` on `<to>_near_river` and aborts. Its message for
     that key deliberately omits the staged-migration route (`R/utils.R:1398-1404`) and
     offers only *"Backfill watershed_group_code in `<to>`, or drop `<to>` and re-run"* —
     and dropping it lets the next custom-AOI run on the same network write the row again.
     Fix 6 creates the state fix 4 refuses.

  Reachability is the same as round 1 recorded for the writer: it needs a network that
  carries `linear_feature_id` and all of `.frs_near_river_check()`'s required columns while
  `watershed_group_code` is partly NULL — which fresh's "network-agnostic" contract admits
  and which commit `20e59e4` ("a NULL watershed group is now addressable") claims to
  support for classify. `IS NOT DISTINCT FROM` on both sides, or dropping the term from the
  read predicate too, closes it as one change; either one alone does not.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness"

- **[severity: fragile]** `R/frs_habitat_classify.R:378-387` vs `:282`, `:286-287`, `:529`
  — round 1's fix 3 (`ignore.case = TRUE`) makes the "caller already holds a transaction"
  path work, and on that path the comment the same commit rewrote becomes false: the DDL
  it says stays outside a transaction now runs inside the **caller's**, holding its locks
  on the shared target until the caller commits.

  The comment, as rewritten by `770fba5`:

  ```r
  # The CREATE, the ALTER and .frs_index_working() stay outside,
  # each its own transaction: CREATE INDEX takes SHARE on the shared target
  # and ALTER TABLE ACCESS EXCLUSIVE, both of which conflict with another
  # worker's open ROW EXCLUSIVE. ... Inside the transaction the DDL would be
  # far worse: the lock would then be held to commit.
  ```

  When `began` is `FALSE` because `dbBegin()` was refused as nested, classify issues no
  `BEGIN` and no `COMMIT` of its own, so `.frs_habitat_target()`'s
  `ALTER TABLE <to> ADD COLUMN IF NOT EXISTS linear_feature_id` (`R/utils.R:116-117`,
  ACCESS EXCLUSIVE) at `:282`, `.frs_index_working()` at `:286-287`, and
  `.frs_index_working(conn, to)` at `:529` — four `CREATE INDEX IF NOT EXISTS` plus
  `ANALYZE` on the shared habitat table — all execute inside the caller's open
  transaction and hold to the caller's `COMMIT`. code-check-infra.md's own sub-bullet is
  the reason this bites even when there is nothing to do: *"`CREATE INDEX IF NOT EXISTS`
  and `ALTER TABLE … ADD COLUMN IF NOT EXISTS` take their table lock before they look."*

  Before fix 3 this path raised at `dbBegin()`, so it could not arise; the branch's new
  test `tests/testthat/test-habitat_partition_293.R:415-437` sanctions it, and it runs on
  one connection against a `pg_temp` table, so it cannot surface the lock. An orchestrator
  that wraps classify in `DBI::dbWithTransaction()` while another worker writes the same
  `to_habitat` gets a block for the length of the outer transaction, which under the
  `statement_timeout` CLAUDE.md prescribes surfaces as a cancelled statement rather than a
  wait. This is **not** the ROW EXCLUSIVE hold already accepted as a tradeoff — that one is
  bounded by classify's own commit; this one is bounded by a caller fresh does not control.
  Issuing only the missing DDL after reading `pg_indexes` / `pg_attribute` (infra's stated
  remedy) removes it on both paths, or the DDL moves behind a `began`-aware guard.
  - **Rule:** code-check-infra.md "Set `statement_timeout` + `lock_timeout` on long DB ops"

- **[severity: fragile]** `R/frs_cluster.R:15-21`, `R/frs_habitat_overlay.R:36-55`,
  `R/frs_order_child.R:117-122` — round 1's fix 9 corrected the key claim in `CLAUDE.md`
  and left three **exported** functions' rendered roxygen asserting the key this branch
  proves insufficient, one of them as copyable SQL.

  - `frs_cluster()`'s `@param habitat`: *"Must carry `watershed_group_code`: `id_segment`
    is unique only within a watershed group, so every join matches both. **A shared
    habitat table holding other groups' rows is therefore safe**"*. The branch's premise
    is that the pair is no longer sufficient on a shared table — one group can now hold
    two jobs' rows — and `.frs_cluster_*()` were all changed to add the parent accordingly.
    This paragraph still states the pre-#293 safety claim as the parameter's contract.
  - `frs_habitat_overlay()`'s "Two join modes" section: *"the `to` table is keyed by
    `(id_segment, watershed_group_code)`"* plus a fenced SQL block showing exactly the
    two-column join `:274-278` no longer emits, and *"The join matches
    `watershed_group_code` as well as `id_segment`, because `id_segment` is unique only
    within a watershed group"*.
  - `frs_order_child()`'s `@section SQL emitted:` fenced block, `:120-121`:
    `WHERE <habitat>.id_segment = s.id_segment AND <habitat>.watershed_group_code =
    s.watershed_group_code` — the code at `:302-314` now emits three conditions.

  These are pkgdown-rendered reference pages, and the `frs_order_child` one is a SQL block
  a reader copies; the two-column form on a shared habitat table is the row-multiplication
  the branch exists to close, and the `frs_cluster` one affirmatively tells the reader not
  to worry about it. The internal siblings have the same drift (`R/frs_habitat.R:1347-1349`
  and `:1742-1745`, *"every join matches `watershed_group_code` too, so they are never read
  or cleared"*), which is `@noRd` and therefore cheaper, but it is the same sentence.
  - **Rule:** code-check.md "Documentation Staleness" ; code-check.md "A fix lands in one
    of two callers that share a harness"

## Notes (not findings)

- **Fix 1 (the three converted joins) and fix 2 (the enumeration test) are both sound**,
  verified mechanically above. The allowlist of four is complete and each entry justified.
- **Fix 7's number formatting is correct**, traced through `.frs_near_river_values()`,
  `q.threshold`, `w.threshold` and the `IN` row-constructor. The `distance_max` literal
  carries no cast while the stored value does, but Postgres resolves `float8 = numeric` via
  the implicit `numeric → float8` cast, and both sides derive from the same `%.10g` text,
  so the comparison is of one double with itself.
- **Fix 4's guard placement is otherwise correct.** `if (length(.frs_cols_of(conn, to)) > 0)`
  skips only a target that does not exist, which `.frs_near_river_table()` then creates
  empty; `CREATE TABLE IF NOT EXISTS` is a no-op on an existing one, so the `cols_to` the
  guard chose its key from and the `cols_to` the delete is built from at `:174` cannot
  differ. The shape mismatch that would make `.frs_persist_delete_key()` raise is caught
  one line earlier by `.frs_near_river_check_shape()`.
- **Fix 5's skip is the safe branch and nothing else depends on `sp_classify` unsafely.**
  With `sp_classify` empty, `near_specs` is a 0-row frame, `near_tbl` is `NULL`,
  `access_thresholds` is `numeric(0)`, the loop runs zero times and the transaction commits
  empty. One asymmetry, failing safe: `.frs_habitat_target()` still runs
  `.frs_null_key_guard()` on `overwrite` alone (`R/utils.R:123`) while the delete is
  `overwrite && length(sp_classify) > 0`, so a call that classifies nothing can still abort
  on a NULL key. Harmless (nothing would have been written), but the guard and the
  statement no longer share a condition.
- `tgt$lfid` is derived from the **habitat** table and passed as `near_river_lfid` to a
  predicate that reads the **near_river** table, whose own `lfid` is derived separately in
  `.frs_near_river_check_shape()`. Two facts, two artifacts, no guard comparing them — but
  they cannot currently differ: both reduce to "the streams table carries
  `linear_feature_id`", because `.frs_habitat_target()`'s `ALTER` always gives `to` the
  column when the source has it, and the shape check refuses a near_river table that
  disagrees. Worth a line in the roxygen if either derivation moves.
- The new transaction test's `deletes` counter (`:366-384`) does distinguish "the DELETE
  was rolled back" from "no DELETE ran", which was round 1's note. It mocks
  `.frs_db_execute()` with a body that calls `DBI::dbExecute()` directly; the real
  `.frs_db_execute()` (`R/utils.R:1113-1115`) is exactly that, so the mock is faithful.
- `frs_near_river()`'s parent join is exact on `id_segment` alone for any table built by
  `frs_network_segment()` / `frs_extract()`: `.frs_add_id_segment()` sets base rows to
  `linear_feature_id` (globally unique) and `frs_break_apply()` derives the rest from
  `max(id_segment) + row_number()`, so no duplicate exists within one working table. On a
  table with per-group `1..n` ids (`fresh.streams`) the join would fan out — but the walk's
  own `PARTITION BY origin_id` already conflates such a table, so the input is unsupported
  before the join is reached. Not a finding.
- `.frs_index_working()` resolves columns through `information_schema.columns` by literal
  schema name (`R/utils.R:690-694`), so for a `pg_temp` target it finds none and creates no
  index — including the `linear_feature_id` index the new delete keys on. Pre-existing on
  `origin/main`, and it affects tests and temp-table callers only (a real
  `fresh.streams_habitat` resolves fine), so noted rather than filed.
- `DESCRIPTION` is still `0.53.0` against `NEWS.md`'s `0.54.0` — the branch's final commit,
  per convention. `NEWS.md`'s migration bullet reads *"each will be given it on the next run
  and then refused"*, which is true of the habitat table and not of `near_river` (which is
  refused outright by its shape check, never altered); the same bullet's second half says so.
