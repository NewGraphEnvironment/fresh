# fresh#293 — code-check round 3

Reviewed at `906f308` (branch `293-custom-aoi-jobs-delete-whole-watershed-g`), the round-2
fix commit. **Nothing in the repository was modified by this review apart from this file**
(probe scripts went to the session scratchpad). Line numbers are against `906f308`.

The tree was clean at review start and had two uncommitted edits by another session at
review end — `R/frs_near_river.R` (the `on.exit` ordering, which is Finding 1 below, fixed
concurrently) and `tests/testthat/test-frs_habitat_classify.R` (a `.frs_group_required`
mock). Both arrived after I had read those files, so my line numbers are as of `906f308`
and `frs_near_river.R`'s are now +7 from `:199` down.

Round 2 found a defect inside a round-1 fix, so this round is an enumeration, not a hunt
for a fifteenth instance.

## Checklist read

- `indexes.txt` — in full. It is the same text this repo's `CLAUDE.md` carries (354 `###`
  headings across the five index blocks), which loads into the session.
- `ck/code-check-infra.md` — **in full** (all 435 lines: Cloud-Init, OpenTofu/Terraform,
  DigitalOcean, Docker/Postgres, Tailscale, every `<!-- evidence -->` block).
- `ck/code-check.md` — `## Mechanisms` read **in full**, lines 38–1255: the prose of all
  fourteen H3s and their evidence tables. From `## Rules that stand alone` I opened
  "Documentation Staleness", "Do not edit files a long test run is reading", "An ordered
  dispatch…", "An assertion that matches an interpolated value…", "A pluralisation
  marker…", "Test the cold/create path…"; the remaining ~24 headings there, plus all of
  Security and Spreadsheets/PDFs, from the index only (no provisioning, no secrets, no
  spreadsheet or PDF in this diff).
- `ck/code-check-r.md` — opened in full: "Cross-function consistency for label/string
  normalization", "An `information_schema` lookup by the literal table name misses what
  Postgres resolves", "Postgres row order is never fixed…", "`sprintf(\"%g\", x)` writes
  `Inf` and `NA`…", "A database driver's value is not a base R type", "Zero-length /
  `paste()`", "`[[` on a named ATOMIC vector", "`$` on a list partial-matches",
  "`ifelse()` with an all-NA test", "`tryCatch(warning = )` DISCARDS the value",
  "`tryCatch()` nests its handlers", "`on.exit()` at a script's top level never fires",
  "`deparse(body(f))` excludes formal defaults", "`deparse()` re-encodes non-ASCII",
  "A `function(...)` mock hides arguments…", "`expect_message(regexp = \"...$\")`",
  "`local_mocked_bindings(.package = )`", "`expect_gt()` and friends take no `info`",
  "testthat counts an uncaught error under `error`", "A `pkg::` call in a test…",
  "`R CMD build` ships every top-level directory…", "testthat's failure snapshots…",
  "`tempfile()` lives in the session tempdir…". ~70 further headings from the index only
  (arrow, duckdb, ggplot2, climr, reticulate, pagedown, earthdatalogin — none in this diff).
- `ck/code-check-shell.md` — index only; the diff contains no shell.
- `ck/code-check-spatial.md` — index only, scanned for applicable headings; 0 opened. The
  diff touches no terra/sf/GDAL/bcdata call. Checked and inapplicable: `sf::st_read()`
  `promote_to_multi`, FWA `upstream_route_measure`, FWA main-flow edge types.

## Mechanism

**One policy written out in several places, and each round's fix landed on the copy the
finding arrived through.** All fourteen earlier findings are instances of it, in two forms:

**(a) N implementations of one rule across N writers.** `.frs_null_key_guard()`'s own
roxygen names the set — *"three writers need it — `.frs_persist_streams()`,
`frs_habitat_classify()` and `frs_near_river()` (fresh#293)"* — and each writer carries
its own copy of five policies. The two older writers agreed, so the third read as the
exception each time, one policy per round:

| policy | `.frs_persist_streams()` | `frs_habitat_classify()` | `frs_near_river()` | found as |
|---|---|---|---|---|
| nested-transaction tolerance | `ignore.case` (0.53.0) | was `fixed` | — | R1 F3 |
| null-key guard **before** the delete | yes (0.53.0) | yes | was **after** | R1 F4 |
| scope the delete to what it reinserts | key alone suffices | species | was unscoped | R1 F7 |
| the degenerate scope is `"FALSE"`, not `NULL` | n/a | was `NULL` | was `NULL` | R1 F5, R2 F1 |
| delete + inserts in one transaction | yes (0.53.0) | added here | was **absent** | R2 F2 |

**(b) N restatements of one fact.** The read key was written out in `CLAUDE.md`, three
exported roxygen blocks, two `@noRd` siblings, a research note and two code comments.
R1 F8/F9 and R2 F4/F5 were each one copy of it, and R2 F3 and F4 were a *writer* fixed
while its *reader* and its *comment* were not.

**Why the loop did not terminate on its own.** The branch's termination instrument —
`test-habitat_partition_293.R:583`, the namespace enumeration — asks a **narrower**
question than the property it certifies. It counts the literal text
`<a>.id_segment = <b>.id_segment` in every parsed function. The property is "every match
of a segment-level row to a stream segment", which can also be written as `GROUP BY`,
`USING (…)`, `IN (SELECT …)`, or built by a second helper rather than by `.frs_key_match()`.
`CLAUDE.md:209` and `research/id_segment_identity.md:133` both now state the universal
("Every such match in fresh is built by `.frs_key_match()`") on that instrument's
authority. That is `code-check.md`, "A proxy is not the property": *"A guard proving that
some check has complete COVERAGE must ask a wider question than the check does."*

### The complete candidate set, per axis

I widened the sweep deliberately: every string literal in `R/` was parsed out
(`getParseData()`, 10 hits) and tested for **five** shapes, not one — `id_segment =`,
`= …id_segment` across newlines, `USING (`, `id_segment IN (`, and
`watershed_group_code = …watershed_group_code`. The superset finds nothing the narrow
regex misses today, so the test's count is correct **now**; it is the question that is
narrow, not the answer.

**Axis 1 — matches of a habitat-style row to a stream segment (23 sites).**

| site | verdict |
|---|---|
| 19 `.frs_key_match()` calls — `frs_cluster.R:290,293,295,414,416,420,492,529,601,630`; `frs_habitat_overlay.R:280`; `frs_habitat.R:1369,1524,1525,1794,1828,1870,1871`; `frs_order_child.R:315` | **below source.** One builder, `lfid` required and `stopifnot`-checked. Every alias the predicate names is projected: `tmp_clusters`/`clustering` gain `s.linear_feature_id` via `lfid_col`; `s`/`st`/`s2`/`s3`/`r` are the streams table; `c` is the cluster temp table |
| 4 allowlisted inline joins, 6 occurrences — `frs_habitat_classify` 1, `.frs_bucket_connected` 2, `.frs_connected_waterbody` 2, `.frs_near_river_sql` 1 | **justified, re-checked.** `frs_habitat_classify:496` joins a per-threshold access temp table built from `table`; `.frs_bucket_connected:1451,1476` join `table` to trace temp tables built from `table`; `.frs_connected_waterbody:1893` joins two CTEs of one statement and `:1925`'s `h` is already pinned by `key`, with `qual_tbl` created and dropped per species (`:1806-1808`, `:1968`) |
| `.frs_near_river_sql()` (`utils.R:563-573`) — a **second implementation** of the same predicate, not `.frs_key_match()` | **above source: Finding 2.** Its `lfid` defaults to `FALSE` where `.frs_key_match()`'s cannot default at all |
| `frs_near_river.R:234` `s.id_segment = w.origin_id` | not this shape (walk origin to streams), group term deliberately dropped by R2 F3's fix; reader and `.frs_group_required()` now agree |
| `GROUP BY`-shaped collapse: `frs_feature_index.R:166-170`, `frs_network_features()` `segment_id_col` | **probed and cleared for the documented target** — see Notes. Reached by the mechanism, not reachable on `fresh.streams` |
| `USING (…)` on the pair: `data-raw/near_river_measure_check.R:77,80` | clear — each `to` is that script's own fresh per-measure table, one job, one group |

**Axis 2 — `frs_habitat()`'s four persist targets.** `to_streams` → #282, keyed on
`linear_feature_id`, one transaction. `to_habitat` and `<to_habitat>_near_river` → this
branch. `to_barriers` (`frs_habitat.R:544-553`, `:686-698`) → still `DELETE … WHERE
blue_line_key IN (…)`, no transaction, positional `INSERT … SELECT *` — **filed as
fresh#294 and accepted out of scope by the owner** (`planning/archive/2026-11-issue-282-persist-delete-key/task_plan.md:71`).
Not a finding; recorded so the enumeration is complete.

**Axis 3 — the five writer policies.** All three writers now agree on all five (table
above). `.frs_persist_delete_sql()` / `.frs_persist_delete_key()` / `.frs_null_key_guard()`
have exactly three callers each (`grep` over `R/`), and `dbBegin` appears in exactly those
three plus `frs_migration_trial.R`. One asymmetry left, below source: `.frs_group_required()`
is called by `frs_habitat_classify():281` and `.frs_near_river_check():340` but not by
`.frs_persist_streams()`, whose only callers are `frs_habitat.R:536` and `:682` — both of
which run `frs_habitat_classify()` first, so the guard is always reached before
`to_streams` is written.

**Axis 4 — the fail-open degenerate scope.** Every helper in the changed files that returns
early on an empty or NULL input and whose result reaches SQL: `.frs_near_river_pairs_in`
(`"FALSE"`), `.frs_rules_to_sql` (`"FALSE"`), `.frs_rule_to_sql` (`"FALSE"`),
`.frs_access_label_filter` (`"FALSE"`), `.frs_fetch_where` / `.frs_resolve_aoi` /
`.frs_order_by` (`""`, correctly meaning "no filter"), `.frs_cluster_both`'s `valid_clause`
(`""`, correctly meaning "no exclusions"), `.frs_find_waterbody_rule` / `.frs_stage_rules` /
`.frs_rule_near_river` (`NULL`, consumed by a NULL-aware reader). **No third member of the
`extra_subset` class.** Both known members are fixed and both have a test
(`test-habitat_partition_293.R:56`, `:402`).

**Axis 5 — `.frs_wsg_in()`'s `key`.** 6 call sites: `frs_cluster.R:148`,
`frs_habitat.R:1370`, `:1526`, `:1795`, `frs_order_child.R:295`,
`frs_habitat_classify.R:518`. All pass the job's own partition key (`tgt$key`, or
`if (lfid) "linear_feature_id" else "watershed_group_code"` derived from the same
`.frs_lfid_pair()`), and the formal `stopifnot`s the three legal values.

**Axis 6 — prose restatements of the read key.** `CLAUDE.md:208-209`,
`research/id_segment_identity.md:118-140`, `frs_cluster.R:17-25`,
`frs_habitat_overlay.R:37-59`, `frs_order_child.R:117-131`,
`frs_habitat_classify.R:148-161`, `frs_habitat_predicates.R:117-125`,
`frs_habitat.R:1347-1350` and `:1744-1749`, `utils.R:1546-1560` — all now state the
three-column key, and `man/*.Rd` is regenerated to match. Residue, all cleared in Notes:
`frs_feature_index.R` (5 statements), `frs_network_segment.R:98-99`,
`research/id_segment_identity.md:79`.

**Axis 7 — the published numbers.** `NEWS.md` 0.54.0's 199 / 0 / 98 / 21 / 125 /
50,808 / 69,956 / 19,148 / 0.38 / 5 groups all re-derive from the two committed CSVs
(`data-raw/logs/habitat_293/summary.csv`, `ratio.csv`). One endpoint has no committed
producer — see Notes.

## Findings

- **[severity: fragile]** `R/frs_near_river.R:146` (with `:202`) — the walk-table cleanup is
  registered on `on.exit()` **before** the rollback handler, so on a real mid-transaction
  failure it runs first, inside the aborted transaction, raises, and **replaces the error the
  caller sees**. The transaction this branch added is for exactly that failure, and its
  diagnosis is what gets destroyed.

  ```r
  on.exit(.frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", walk_tbl)),
          add = TRUE)                                              # :146
  ...
    on.exit(if (!committed) try(DBI::dbRollback(conn), silent = TRUE),
            add = TRUE)                                            # :202
  ```

  Postgres refuses every command but `COMMIT`/`ROLLBACK` in an aborted transaction, so the
  `DROP TABLE IF EXISTS` raises `25P02 current transaction is aborted, commands ignored
  until end of transaction block`. Measured, R 4.5.2: with handlers in this order, **both
  run** (so the rollback does happen and no rows are lost), and the condition the caller
  receives is the **first handler's**, not the body's:

  ```
  handlers: drop,rollback
  caller sees: 25P02 aborted          # body raised "statement timeout"
  ```

  So a `statement_timeout` on `.frs_near_river_walk_sql()` — which the same commit's comment
  calls *"the pipeline's most timeout-prone statement"* — surfaces as "current transaction is
  aborted", naming the cleanup rather than the walk. Neither sibling writer has this: both
  register only the rollback (`frs_habitat_classify.R:419`, `utils.R:1724`), so it is one
  writer of three again.

  **Neither of the branch's two transaction tests can reach it.** Both mock
  `.frs_db_execute()` with a body that raises **before** reaching `DBI::dbExecute()`
  (`test-habitat_partition_293.R:385-388`, `:565-569`), so no statement reaches the server
  and the transaction is never put into the aborted state — the only state in which the
  handler ordering matters. The fix is to register the walk-table drop after the
  transaction block, or to wrap it in `try()`.
  - **Rule:** code-check.md "A fixture that cannot reach the failure mode"

- **[severity: fragile]** `R/frs_habitat_predicates.R:166` and `R/utils.R:554` —
  `near_river_lfid` / `lfid` default to `FALSE` on the **exported** entry point, so the
  parameter that closes this issue's read hole leaves it open for any caller that does not
  know to pass it, while the sibling builder for the same predicate refuses to default:

  ```r
  frs_habitat_predicates <- function(sp_params, model = "cw",
                                     near_river_table = NULL,
                                     near_river_lfid = FALSE)      # :164-166
  .frs_key_match <- function(hab, streams, lfid) {
    stopifnot(is.logical(lfid), length(lfid) == 1, !is.na(lfid))   # utils.R:1568
  ```

  The two halves of the change do not ship together for an outside caller. From 0.54.0 the
  narrowed delete is automatic — `frs_habitat_classify()` stops removing the rest of the
  group from `<to>_near_river` whether or not anyone passes `near_river_lfid` — so the table
  begins holding two jobs' rows in one group, while a caller re-deriving the predicate gets
  0.53.0's short-key `EXISTS` and can pass `near_river` on a distance measured for a
  different segment. That re-derivation is a real pattern, and against this package
  specifically: `code-check.md`'s own link#302 row records link building a classifier from
  fresh's rules rather than asking fresh for the compiled predicate.

  The roxygen (`:117-126`) states the consequence honestly, and `NEWS.md` names the default,
  so this is a deliberate backward-compatibility choice rather than an oversight — but it is
  the one place in the branch where the unsafe value is what you get by omission.
  `near_river_lfid` cannot be derived inside the function (it has no connection), so the
  remedy is to make it **required** whenever `near_river_table` is non-`NULL`, which is the
  only call shape where it can matter.
  - **Rule:** code-check.md "A guard that fails toward pass"

- **[severity: fragile]** `dev/mutation_sweep_sites_habitat_293.csv` — the sweep that is
  meant to terminate this review covers **3 of the 19** `.frs_key_match()` call sites, and
  the 3 are exactly the ones round 1 found broken. The list was written from the instances
  found, not from the population.

  The three rows are `.frs_connected_waterbody`'s `("hr","s2")`, `("hr","s2")` and
  `("hs","s3")`. The other 16 — all ten in `frs_cluster.R`, `frs_habitat_overlay.R:280`,
  `frs_habitat.R:1369`, `:1524`, `:1525`, `:1794`, `frs_order_child.R:315` — have no row. A
  site changed from `lfid` to `FALSE` at any of those would be invisible, because the one row
  that does cover the builder (`"293 key adds parent segment"`, `if (lfid)` inside
  `.frs_key_match`) goes red whichever call site happens to exercise it first:
  `code-check.md`, *"A mutation applied to N sites at once certifies coverage of exactly one
  of them… Mutate one site per run, and name the site in the row."*

  `planning/active/task_plan.md:220` still has the sweep unchecked, so it has not run yet and
  the list is free to widen now. Six more sites with the same property, also unlisted:
  `.frs_wsg_in()`'s `key` at its six call sites (Axis 5).
  - **Rule:** code-check.md "Restore the bug and prove the guard fires"

## Notes (not findings)

- **`frs_feature_index()` is reached by the mechanism and is not reachable — probed, both
  ways.** It is the strongest remaining candidate on Axis 1 and it does not survive
  measurement, so the probe is recorded rather than the suspicion. Its roxygen says *"one
  row per segment of `segments`"*, indexed on `(id_segment, watershed_group_code)`
  (`:11-15`, `:39-43`, `:186`), with `segments = "fresh.streams"` in both examples and an
  example join on exactly that pair (`:58-68`); the body does
  `GROUP BY s.<col_segment_id>, s.watershed_group_code` (`:170`) and carries no
  `linear_feature_id` through. On the branch's premise — #282 narrowed the `to_streams`
  delete to `linear_feature_id`, so a whole-group run followed by a custom-AOI run in the
  same group leaves two jobs' rows, 81 of 275 derived ids colliding — that `GROUP BY` would
  merge two different segments into one row whose feature array is the union of both, with
  no column left to separate them, and the enumeration test cannot see it because it counts
  equalities and this is a `GROUP BY`.

  It cannot happen on the documented target. Measured on the shared instance just now:
  `fresh.streams` carries `streams_pkey`, `CREATE UNIQUE INDEX … USING btree (id_segment,
  watershed_group_code)`, so the colliding `INSERT` aborts with a duplicate key and
  `.frs_persist_streams()`'s transaction (0.53.0) rolls it back — loud, and #282's territory,
  not a silent collapse. Over the whole population of relations carrying all six columns
  `frs_feature_index()` reads, **322 relations, 3 without a unique index on the pair** — and
  a collision needs a *shared* one among those three, which a single-job working table cannot
  be. `frs_network_features(segment_id_col = "id_segment")` groups by `id_segment` alone,
  which is unique inside any one `aoi` group; without an `aoi` it is #218/#277's known
  cross-group case, pre-existing. Same verdict for `frs_network_segment.R:98-99`'s example
  comment and `research/id_segment_identity.md:79` (*"`(id_segment, watershed_group_code)` is
  the key to join on, and it currently holds on `fresh.streams` with 0 duplicate pairs"* —
  hedged on the measurement, present-tense on the rule, and the same file's `:133` paragraph
  explains why the rule is conditional). Worth one sentence somewhere that the pair is
  enforced unique on `fresh.streams`, which is what makes these safe; nothing to fix.

- **`frs_near_river(wsg_code = <code>)` discards every other `(measure, threshold,
  distance_max)` the table holds for that group**, because `.frs_persist_delete_sql()`
  deliberately drops `extra_subset` from the whole-group branch. Inside
  `frs_habitat_classify()` this is harmless and consistent — the whole-group habitat delete
  is unscoped too, so both tables are wholesale-replaced for the group together. For a direct
  caller it is an undocumented consequence: `@param wsg_code` (`:103-110`) describes only the
  ground scope, while `@examples` (`:143-150`) accumulates two measures in one `to` and then
  `GROUP BY 1, 2`s both. The example passes the default `NULL`, so it still works; a reader
  who adds `wsg_code` to it loses the first pair. One clause in `@param wsg_code` would close
  it. The species half of this is the accepted tradeoff; this is the same decision one axis
  over, and the roxygen's justification is written only in terms of species.

- **`NEWS.md:14`'s "across 2 to 125 groups" has no committed producer for its lower bound.**
  `summary.csv` carries `groups_max` (125, which checks out) and `n_multi_group` (21) but no
  minimum; the min is ≥ 2 by the definition of the subset, so the sentence is true at worst
  imprecisely, and the detail file that would settle it (`tables.csv`) is gitignored by
  design. Adding `groups_min` over `sh` to `summary_rows` would make the published range
  re-derivable. Every other number in that release note does re-derive from the two
  committed CSVs, checked one at a time.

- **The habitat target gains `linear_feature_id` but no index on it until the end of the
  first migrated run.** `.frs_habitat_target()` `ALTER`s the column in (`utils.R:116-119`)
  and the delete keys on it immediately (`frs_habitat_classify.R:433`), while
  `.frs_index_working(conn, to)` runs at `:529`, after the commit. So the first run's delete
  is a sequential scan. `.frs_near_river_table()` handles the same case explicitly
  (`frs_near_river.R:462-469`, *"The delete keys on it, and on a first migrated run no index
  exists yet"*), which is the asymmetry; performance only, and self-correcting after one run.

- **Verified sound, so recorded rather than re-flagged.** `sp_classify` is derived from
  `species_params` by `vapply` over it (`frs_habitat_classify.R:217-231`), and the classify
  loop iterates the same object, so the delete's species set and the insert's cannot drift —
  one producer. `.frs_wsg_code_check()` now refuses an `anyNA(have)` group rather than
  dropping it, which closes R1 F4's reachability route. `.frs_near_river_check()` runs the
  null-key guard from `.frs_cols_of(conn, to)` **before** `.frs_near_river_table()` creates
  the table, and the delete's `cols_to` is re-read after; the only case where the two differ
  is a target that did not exist, which is then created empty. `data-raw/audit_habitat_293.R`
  now guards `do.call(rbind, rows)` returning `NULL` (`:167-173`), which was round 1's note.
  `.frs_cluster_both`'s `valid_clause <- if (length(all_valid) == 0) ""` is the *correct*
  direction for its statement (no exclusions ⇒ strip every cluster), not an instance of the
  `extra_subset` class.

- **Non-ASCII in code tokens:** parsed every `R/` and `tests/testthat/` file and tested each
  `STR_CONST` / `SYMBOL` the way `R CMD check` does. The only hits are five `test_that()`
  titles containing em dashes, all pre-existing and none in `R/`. Nothing this branch added.
