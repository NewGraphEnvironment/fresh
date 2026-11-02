# fresh#293 — code-check round 1

Reviewed at `fd96848` (branch `293-custom-aoi-jobs-delete-whole-watershed-g`). `R/` is
unchanged since the supplied diff was taken (`fd96848` touched only
`tests/testthat/test-habitat_partition_293.R`, `planning/`), so line numbers below are
against the live tree. Nothing in the repository was modified by this review apart from
this file.

## Checklist read

- `indexes.txt` — in full.
- `ck/code-check-infra.md` — in full.
- `ck/code-check.md` — `## Mechanisms` in full (all 14 H3 bodies, tables skipped);
  from `## Rules that stand alone` onwards read via the index only (~20 headings not
  opened in full: the cloud-init / CI / spreadsheet / PDF / security material that this
  diff does not touch, plus "Documentation Staleness" and "An assertion that matches an
  interpolated value cannot see the claim around it", which I read from the index line).
- `ck/code-check-r.md` — read in full: "Cross-function consistency for label/string
  normalization", "An `information_schema` lookup by the literal table name misses what
  Postgres resolves" (carries the no-op-DDL lock note and the correlated-subquery note),
  "A database driver's value is not a base R type", "Postgres row order is never fixed",
  "`sprintf(\"%g\")` writes `Inf` and `NA`", plus index lines for the testthat family
  (`local_mocked_bindings`, `skip_if_not`, `expect_gt(info=)`, `tolerance`), `nzchar(NA)`,
  `ifelse()` all-NA, `$` partial matching, `[[` on an atomic vector, `paste()`
  zero-length, `match()` and NA. ~70 headings read from the index only.
- `ck/code-check-shell.md` — index only; the diff contains no shell.
- `ck/code-check-spatial.md` — index only, checked for applicable headings; the diff
  touches no terra/sf/GDAL/bcdata code. (Index lines scanned, 0 opened.)

Mechanical check run: parsed all eight changed `R/` files and compared `sprintf()`
conversion-spec counts against positional argument counts — 251 calls, all with literal
format strings, **0 mismatches**. Argument *order* for every changed template was then
checked by hand (`.frs_cluster_upstream`, `.frs_cluster_downstream`, `.frs_cluster_both`
phase 2 and 3 and its final UPDATE, `.frs_bucket_connected`, `.frs_rearing_distance`,
`.frs_connected_waterbody`, `frs_order_child`, the classify INSERT, the near_river
INSERT) — all correct, and every CTE/temp table the new `.frs_key_match()` pins against
does project the columns the predicate names.

## Findings

- **[severity: bug]** `R/frs_habitat.R:1820-1822`, `1852-1854`, `1859-1861` —
  `.frs_connected_waterbody()` still spells **three** habitat-to-streams joins on the
  short key, with the alias order reversed so they read differently:

  ```
  1821:     INNER JOIN %s hr ON s2.id_segment = hr.id_segment
  1822:       AND hr.watershed_group_code = s2.watershed_group_code     -- origins_sql
  1853:       INNER JOIN %s hr ON s2.id_segment = hr.id_segment          -- rearing_segs CTE
  1860:       INNER JOIN %s hs ON s3.id_segment = hs.id_segment          -- spawn_upstream CTE
  ```

  The same function's subtractive UPDATE and its counts *were* converted (`key`, `part`
  at `R/frs_habitat.R:1791-1793`), so the parent segment is enforced when clearing
  `spawning` but not when deciding which segments are rearing origins or spawn
  candidates. On the branch's own premise — one group can now hold two jobs' rows at a
  colliding `id_segment`, 81 of 275 measured — these three reads pick up another job's
  habitat row and produce extra downstream-trace origins, extra `rearing_segs` and extra
  `spawn_upstream` rows. `grep -rn "watershed_group_code =" R/*.R` and a scan of every
  `id_segment =` occurrence in `R/` confirm these are the only three left (the one in
  `.frs_near_river_sql()` at `R/utils.R:564-567` carries the `lfid` option).
  - **Rule:** code-check-infra.md "Joining on a per-tenant key (e.g. `id_segment` per-WSG) against a multi-tenant table is cartesian"

- **[severity: fragile]** `tests/testthat/test-habitat_partition_293.R:396-402` — the
  enumeration test that is supposed to make the finding above impossible cannot see it.
  It searches each parsed body for the literal `"id_segment = s.id_segment"`:

  ```r
  txt  <- paste(deparse(body(fns[[nm]])), collapse = "\n")
  hits <- gregexpr("id_segment = s.id_segment", txt, fixed = TRUE)[[1]]
  ```

  `.frs_connected_waterbody` is in `fns`, and its three remaining inline joins are
  spelled `s2.id_segment = hr.id_segment` / `s3.id_segment = hs.id_segment`, which that
  string does not match (`grep -c "id_segment = s\.id_segment" R/frs_habitat.R` → **0**,
  while the three `s2.`/`s3.` spellings are present). So the assertion is 0 == 0 for the
  one function that still has the defect. Two further reasons it reads as stronger than
  it is: `.frs_run_connectivity` is in the list and contains no SQL at all (it is a pure
  dispatcher, `R/frs_habitat.R:1206-1305`), and the scan is over text rather than over
  the parse tree, so one more alias spelling defeats it again. A check that enumerates
  the *joins* (e.g. every `id_segment` equality in each body, asserting each is one
  `.frs_key_match()` produced) would have to ask a wider question than the fix did.
  - **Rule:** code-check.md "A fixture that cannot reach the failure mode" ; code-check.md "A proxy is not the property"

- **[severity: bug]** `R/frs_habitat_classify.R:392` — the nested-transaction tolerance
  never fires, so the case the comment at `:382-385` says "is not an error here" aborts
  the call:

  ```r
  if (grepl("nested transaction", conditionMessage(e), fixed = TRUE)) {
  ```

  RPostgres raises `"Nested transactions not supported."` — capital N, plural. Measured
  on this machine against the installed driver:

  ```
  getMethod("dbBegin","PqConnection") -> stop("Nested transactions not supported.", call. = FALSE)
  grepl("nested transaction", "Nested transactions not supported.", fixed = TRUE)  #> FALSE
  ```

  `fixed = TRUE` is case-sensitive, so the branch falls to `stop(e)` and
  `frs_habitat_classify()` fails for any caller that already holds a transaction
  (`DBI::dbWithTransaction`, `frs_migration_trial()`, an orchestrator such as link's
  pipeline). The sibling copy of the identical rule, shipped in 0.53.0, gets it right —
  `R/utils.R:1672` uses `ignore.case = TRUE` — and there is a test for that one
  (`tests/testthat/test-utils.R:524-526`, a real `dbBegin()` then
  `expect_no_error(.frs_persist_streams(...))`). No equivalent test exists for
  `frs_habitat_classify()`, which is why the divergence is invisible. The two readers of
  one rule should share a helper.
  - **Rule:** code-check-r.md "Cross-function consistency for label/string normalization" ; code-check.md "A fix lands in one of two callers that share a harness"

- **[severity: bug]** `R/frs_near_river.R:176-179` — the new NULL-key guard runs **after**
  the destructive DELETE, so when it fires the partition is already gone and the walk
  never writes it back:

  ```r
  .frs_db_execute(conn, .frs_persist_delete_sql(
    to, table, wsg_code, cols_to, cols_from))
  .frs_null_key_guard(conn, to, .frs_persist_delete_key(
    to, table, wsg_code, cols_to, cols_from))
  ```

  Both of the other two writers put this guard before the write: `.frs_habitat_target()`
  runs it before anything (`R/utils.R:122-123`, and `R/frs_habitat_classify.R:276-282`
  explains that placement deliberately), and `.frs_persist_streams()` runs it before the
  delete (`R/utils.R:1638`). `frs_near_river()` already has a writes-nothing pre-flight
  built for exactly this reason — `.frs_near_river_check()` ("a stop inside
  `frs_near_river()` would come after classify had deleted the group's habitat rows",
  `R/frs_near_river.R:226-236`) — and the guard was not added to it.

  Reachable through the `watershed_group_code` key: `.frs_wsg_code_check()` drops NA
  groups before its `setequal()` (`R/utils.R:1444`, `have <- have[!is.na(have)]`), so a
  `near_river` table holding any NULL-group row passes that check, the whole-group DELETE
  removes the named group's rows, and then the guard raises — leaving the group deleted
  with nothing inserted. That is this issue's loss reached another way, in the table the
  release note calls a rebuildable cache; the only recovery is the `drop <to> and re-run`
  the message names, because a re-run hits the same guard after deleting again.
  - **Rule:** code-check.md "A guard that fails toward pass" ; code-check-infra.md "Two-statement DELETE/INSERT into a persist table is not atomic"

- **[severity: bug]** `R/frs_habitat_classify.R:408-418` — when no requested species
  classifies, the species predicate is dropped and the delete reverts to wiping the whole
  partition for **every** species, with nothing inserted afterwards:

  ```r
  .frs_db_execute(conn, .frs_persist_delete_sql(
    to, table, wsg_code, tgt$cols_to, tgt$cols_from,
    extra_subset = if (length(sp_classify) > 0) {
      sprintf("species_code IN (%s)", ...)
    }))
  ```

  `if (FALSE) {...}` is `NULL`, so `extra_subset` is `NULL` and
  `.frs_persist_delete_sql()` emits the unscoped
  `DELETE FROM <to> WHERE linear_feature_id IN (SELECT linear_feature_id FROM <table>)`.
  `sp_classify` is `character(0)` whenever every element of `species` lacks a `params`
  entry or a `params_fresh` row (`R/frs_habitat_classify.R:217-232`), and the only input
  check is `stopifnot(is.character(species), length(species) > 0)` at `:182`. The
  classify loop then iterates zero times, so the AOI's rows for all species are removed
  and none written back — the exact shape #293 fixes, and a direct contradiction of the
  `overwrite` contract this branch added ("with `NULL` it is the ground `table` holds
  **and only the species this call classifies**"). Reachable from `frs_habitat()` too:
  the auto-detect path filters species against `params`/`params_fresh`
  (`R/frs_habitat.R:308-312`) but an explicit `species =` argument is passed through
  unfiltered (`:305-306`), so one mistyped code is enough. Scoping to the empty set
  (delete nothing) or refusing the call are both safe; falling back to "all species" is
  not.
  - **Rule:** code-check.md "Zero-length, empty, and unset are three different things" ; code-check.md "A guard that fails toward pass"

- **[severity: fragile]** `R/frs_near_river.R:194-205` — the join that fetches the parent
  segment is an INNER JOIN that also equates `watershed_group_code`, so any walk row
  whose group is NULL is silently dropped from the insert:

  ```r
  if (lfid) sprintf("
   JOIN %s s ON s.id_segment = w.origin_id
     AND s.watershed_group_code = w.watershed_group_code", table) else ""
  ```

  The comment directly above it (`:190-193`) states the join is exact on `origin_id`
  alone — "`origin_id` is an id_segment, unique within the working table, so the join is
  exact" — so the extra equality buys nothing and costs the NULL case. `frs#225` is
  about exactly that state, and the classify INSERT handles it (it joins accessibility on
  `id_segment` only, `R/frs_habitat_classify.R:476`), so a NULL-group segment gets a
  habitat row while its `near_river` row vanishes, and every `near_river` predicate for
  it reads FALSE — under-classified habitat with no error, which is the harm the release
  note describes for the old defect. I could not demonstrate it inside fresh's own FWA
  pipeline (`fwa_stream_networks_sp.watershed_group_code` is NOT NULL, and the `#225`
  test's fixture `pg_temp.p293_nofwa` has no `linear_feature_id`, so `lfid` is FALSE
  there); it needs a network carrying `linear_feature_id` with a partial group column,
  which the package's "network-agnostic" contract admits. Dropping the group term, or
  `IS NOT DISTINCT FROM`, closes it.
  - **Rule:** none — candidate: "an equality join on a nullable column silently drops rows an outer join or `IS NOT DISTINCT FROM` would keep"

- **[severity: fragile]** `R/frs_near_river.R:176-177` vs `R/frs_habitat_classify.R:412`
  — the species narrowing was added at one `.frs_persist_delete_sql()` call site and not
  the other, so the two coupled stores now overwrite different amounts of ground.
  `frs_habitat_classify()`'s habitat delete keeps another species' rows; `frs_near_river()`'s
  delete passes no `extra_subset`, so it removes **every** `(measure, threshold,
  distance_max)` triple for the job's parent segments and writes back only the triples
  the current call's species need (`near_specs` comes from `sp_classify`,
  `R/frs_habitat_classify.R:264`). So the documented new behaviour — "a CO-only re-run
  replaces CO's rows and leaves BT's", which `tests/testthat/test-habitat_partition_293.R`
  asserts — leaves BT's surviving habitat rows with no `near_river` rows behind them.
  Anything that re-evaluates the persisted predicates against the persisted table (link's
  `lnk_habitat_validate()` does) then disagrees for reasons unrelated to the model. The
  fix is symmetric: pass the triples the walk will write as `extra_subset`.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness"

- **[severity: fragile]** `R/frs_habitat_classify.R:386-510` — the new transaction holds
  `ROW EXCLUSIVE` on the shared `to` from the DELETE through every species INSERT (and
  the verbose count queries between them), where 0.53.0 held it per autocommitted
  statement. Two no-op DDL statements on that same shared table still run outside any
  transaction and take a conflicting lock before they check whether there is work to do:
  `.frs_index_working(conn, to)` at `:516` issues four `CREATE INDEX IF NOT EXISTS`
  (SHARE — conflicts with ROW EXCLUSIVE) plus `ANALYZE`, and `.frs_habitat_target()`
  issues `ALTER TABLE … ADD COLUMN IF NOT EXISTS linear_feature_id`
  (`R/utils.R:116-117`, ACCESS EXCLUSIVE) on the migration run. In `frs_habitat()`'s
  mirai mode every worker runs both against one `to_habitat`
  (`R/frs_habitat.R:670-675`), so one worker's index step now blocks for the length of
  another worker's whole classify, and because Postgres does not let later requests jump
  a queued ACCESS EXCLUSIVE / SHARE request, a third worker's DELETE queues behind it.
  The in-code comment at `:377-381` reasons only about deadlock; I agree there is no lock
  cycle (each DDL is its own transaction), so this is serialization rather than deadlock
  — but under the `statement_timeout` CLAUDE.md prescribes for long DB ops it surfaces as
  a cancelled statement, and with no timeout as an apparent hang. Reading
  `pg_indexes` / `pg_attribute` and issuing only the missing DDL removes it.
  - **Rule:** code-check-infra.md "Set `statement_timeout` + `lock_timeout` on long DB ops"

- **[severity: fragile]** `CLAUDE.md:208` — the branch invalidates a rule in the file
  every session loads, and did not update it. It still says persisted tables including
  `fresh.streams_habitat_<sp>` "key on `(id_segment, watershed_group_code)` — always join
  on both". The roxygen example (`R/frs_habitat_classify.R:139-161`) and
  `research/id_segment_identity.md` were both corrected to the three-column key, and
  `tests/testthat/test-habitat_partition_293.R:166-169` asserts duplicates on
  `(id_segment, watershed_group_code, species_code)` now exist in a shared table — so
  `CLAUDE.md` is now the one place that tells the next reader to use the key this branch
  proves is insufficient.
  - **Rule:** code-check.md "Documentation Staleness"

## Notes (not findings)

- `DESCRIPTION` is still `Version: 0.53.0` while `NEWS.md` carries a `# fresh 0.54.0`
  section and six roxygen blocks reference 0.54.0 behaviour. Release bookkeeping, and the
  convention puts the bump in the branch's final commit — flagging only so it is not
  forgotten.
- `R/frs_habitat.R:1366` and `:1410` call `.frs_lfid_pair(conn, habitat, table)`
  twice in `.frs_bucket_connected()` and reassign `key` from the second call. Four extra
  catalog round trips per species; the two derivations read the same two tables in the
  same call so they cannot disagree. Not a defect.
- `tests/testthat/test-habitat_partition_293.R:344-381` (the transaction test) asserts
  only `count == n0` after the forced failure. That distinguishes the fix from 0.53.0's
  behaviour correctly (the old autocommitted pair would leave `n_CO` rows), but it does
  not distinguish "the DELETE was rolled back" from "no DELETE ran", because `calls`
  counts INSERT statements only. The comment on `:377` says "the delete and one insert
  did run"; `calls` is evidence for the insert only.
- `data-raw/audit_habitat_293.R` interpolates catalog-discovered names through
  `DBI::dbQuoteIdentifier()` per part (`:116-118`) rather than
  `.frs_validate_identifier()`, which is the right call and is explained in the comment.
  The committed outputs (`summary.csv`, `ratio.csv`) carry no schema names; `tables.csv`
  is gitignored. `tables <- do.call(rbind, rows)` is `NULL` if every table is skipped,
  and `split(NULL, NULL)` then errors — a one-off audit script, so noted rather than
  filed.
