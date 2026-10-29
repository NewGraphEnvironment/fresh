# Task: frs_network_features(): an existence mode that answers 'any feature downstream?' without building the arrays (#281)

## Problem

`frs_network_features()` returns, per segment, the array of every feature downstream (or upstream). Some callers reduce that array to one boolean per segment. NewGraphEnvironment/link#394 measured the cost of building what is thrown away: in SETN the CH walk produces 4.83 M (segment, feature) pairs and spills a 526 MiB sort to disk, and #272's prefilter makes that group's walks only 1.2× faster, because the time is in the output, not the probing.

## Context (from plan mode)

`frs_network_features()` (`R/frs_network_features.R`, 0.46.0) returns every feature
downstream or upstream of each segment as an array. link's `lnk_pipeline_access()` reduces
the natural-barrier walks to `id %in% result$id` and throws the arrays away. link#394 measured
SETN's CH walk at 4.83 M (segment, feature) pairs with a 526 MiB sort spilled to disk, so
#272's prefilter only made it 1.2x faster: the time goes into building the output. An
existence mode lets those callers skip the arrays and keep #272's temp table and prefilter.

The local fwapg (`FRESH_PG*`, `docker/`) holds `fresh_default.streams` for SALR (11,392
segments), CHWK (14,347), LFRA (58,209), SETN (188,554), and the `barriers_<sp>_access`
views, so every measurement runs locally, as #272's did (`data-raw/network_features_prefilter.R`).

## Decided at the gate

- **Shape (user, 2026-10-28):** `result = "exists"` returns one row per segment that has at
  least one feature: `<segment_id_col>` and a logical `has_features` (always TRUE). Segments
  with none are left out, as in the array mode. link switches by adding one argument.
- **Argument:** `result = c("ids", "exists")`, default `"ids"`, as the issue proposes. The
  array mode does not change.
- **EXISTS vs DISTINCT is settled by measurement in Phase 1**, not up front: the faster of the
  two that gives identical sets in all four groups. One form ships; no internal switch.
- **One row per distinct id**, as the array mode's `GROUP BY` gives, whichever form wins (an
  `EXISTS` over a segments table with a repeated id would otherwise return it twice).

## Phase 1: Measure the two candidate forms
- [x] `data-raw/network_features_exists.R`, modelled on `data-raw/network_features_prefilter.R`:
      local fwapg via `FRESH_PG*`, refuses to start when another client backend is active,
      builds the scoped walk with the package's own `.frs_walk_scope()` / `.frs_walk_prefilter()`,
      and runs three SQL texts on the same temp table: the array mode as sent, `EXISTS`,
      `SELECT DISTINCT` over the join
- [x] Views `barriers_ch_access`, `barriers_bt_access`, `barriers_st_access` (the three natural
      shapes); `include_equivalents = TRUE`, as link calls it; runs interleaved per walk
- [x] Oracle: the array walk's row set (the segments it returns, as link reads them), as a
      count and an md5 of the sorted ids, must equal each candidate's (review B2: not
      `lengths > 0`, which drops segments whose only features have NULL ids)
- [x] SALR, CHWK, LFRA first; SETN only after, with a 30 min statement timeout and timed-out
      runs written as censored (the array form alone ran past 10 min there)
- [x] Log to `data-raw/logs/network_features_exists_281/` (tsv + README); `EXPLAIN (ANALYZE,
      BUFFERS)` of each candidate on one group, to see which plan the semi-join gets
- [x] Record the choice and its numbers in `findings.md`

## Phase 2: Tests (written to fail first)
- [x] `tests/testthat/test-frs_network_features.R` (mocked, `mock_nf_db()`): `result` is
      validated by `match.arg`; `"exists"` sends no `array_agg` and no `ORDER BY`; the scoped
      downstream path still builds the temp table and walks the prefiltered features; the
      unscoped `aoi` filter and `direction = "upstream"` compose; the result has columns
      `<segment_id_col>` and logical `has_features`, also with zero rows; `"ids"` SQL is
      unchanged (byte-identical to the current composition)
- [x] `tests/testthat/test-frs_network_features-local.R` (SKGT fixture, `nf_local_features()`):
      exists ids equal the array mode's ids for both `include_equivalents`, the temp table is
      gone afterwards; one upstream case (required, review G4); a repeated-id segments table
      and an all-NULL-id features table (review G2, B2)
- [x] Restore-the-bug check: drop the prefilter from the exists path, and drop the dedupe;
      confirm a test goes red for each (in a scratch copy, then restore)

## Phase 3: Implement
- [x] Add `result = c("ids", "exists")` to `frs_network_features()`; branch only the final
      `SELECT`: the scope, prefilter, predicate and `aoi` filter are shared
- [x] roxygen: `@param result`, the `@return` for exists, an example; note that its ids equal
      the array mode's rows (review B2); `devtools::document()`
- [x] Tests pass (`devtools::test()` with the grep pattern), `lintr::lint_package()` clean

## Phase 4: Verify on real groups and record
- [x] Re-run the Phase 1 script against the shipped function (ids vs exists) on SALR, CHWK,
      LFRA, SETN: identical sets, and the times, including end to end through the function
      (`fn_ids` / `fn_exists`: transfer and R parse, review A1)
- [x] Add a section to `research/fwa_downstream_walk.md` (what an existence walk costs against
      the array walk, and which form, with the log prefix); update `research/README.md`'s row
- [ ] NEWS 0.47.0 entry and `DESCRIPTION` bump as the branch's last commit

## Owed at the end (reported, done after merge)

- [ ] link#394 lever 1: switch the natural-barrier walks to `result = "exists"` in link, which
      needs a fresh floor bump and keeps the array form for any table link also uses as a
      source (its walk cache is per table). A link PR, not this one.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: the mocked tests pin the SQL shape; the SKGT local test pins exists == array
mode's non-empty ids on real FWA data through both prefilter arms; the Phase 4 run pins it on
link's real barrier views in four groups, with times, SETN being the group that should move.

