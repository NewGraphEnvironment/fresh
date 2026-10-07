# Code check, round 2: R CMD check fixes (diff_checkfix.patch)

Verdict: **NOT CLEAN. One real gap. The F2 fix is right but stops one step short.** Everything else is clean, including F1 and F3.

## G1. The F2 call sites still fail, one step later, at `frs_classify(breaks=)`

Files:
- `vignettes/habitat-pipeline.Rmd`, static block, lines ~138-152
- `data-raw/vignette_habitat_pipeline.R`, lines ~118-133
- `data-raw/pipeline_wsg.R`, lines ~85-96

All three now run `frs_break_find()`, then `frs_feature_find(append = TRUE)`, then `frs_break_apply()`, then `frs_classify(label = "accessible", breaks = <tbl>)`.

`.frs_classify_breaks()` (R/frs_classify.R) reads `b.wscode_ltree` and `b.localcode_ltree` from the breaks table in its cross-BLK `NOT EXISTS`. Nothing in that chain adds those columns:
- `frs_break_find()` writes `blue_line_key, downstream_route_measure, [gradient_class,] label, source`.
- `frs_feature_find()` writes the same four columns.
- `frs_break_apply()` never touches the breaks table.

Only `frs_habitat_access()` adds them, through `.frs_enrich_breaks()`. A qualified column reference inside the subquery does not fall back to an outer scope, so Postgres rejects the statement at parse time. Read-only probe against local fwapg:

```
SELECT 1 FROM (SELECT 1 AS blue_line_key, 0::double precision AS downstream_route_measure) b
WHERE b.wscode_ltree IS NOT NULL
-> ERROR:  column b.wscode_ltree does not exist
```

This is pre-existing. The column became required in #75 (bb0a8a4, 2026-04-04), and #95 then broke the step before it. But the purpose of F2 was to make these call sites runnable. All three still abort, and nothing catches it:
- The vignette block is a static block that is never evaluated.
- The data-raw scripts are not run in CI.
- `test-frs_classify.R` covers `breaks=` only through mocked SQL.

Anyone who copies the vignette block hits the error.

**Fix: replace the find + append pair with the exported wrapper that already does this.** It covers the gradient find, the appended sources, `.frs_enrich_breaks()` and indexing:

```r
frs_habitat_access(conn, "working.byman_habitat",
  threshold = co_fresh$access_gradient_max,      # access_gradient_max / access_gradient in the scripts
  to = "working.breaks_access",
  break_sources = list(list(table = "bcfishpass.falls_vw",
                            where = "barrier_ind = TRUE")))
```

The rest of the chain is unchanged: `frs_break_apply()` and `frs_classify(breaks=)`. Update the vignette prose to name `frs_habitat_access()`, or keep naming the two finders and say the wrapper runs both plus the ltree enrichment. This also removes the hand-written `overwrite = FALSE, append = TRUE` pair from three places.

## Answers to the specific questions

**Is the label-NULL claim true?** Yes, for every consumer these scripts use.
- `.frs_classify_breaks()` never reads `label`. It uses only BLK, measure and ltree.
- Pre-#95 table mode also wrote `NULL::text AS label` when no label was given, so output is unchanged from the last version that worked.
- Caveat, not a defect here: `frs_habitat_classify()` reads labels through `.frs_access_label_filter()`. There a NULL label does not block, and neither does the `'gradient'` label from `frs_break_find(threshold=)`. A reader who points that function at `working.breaks_access` would get no blocking at all. The scripts and vignette do not do this.

**Does dropping `aoi` change what the scripts select?**
- *Against the last working code:* no. Pre-#95 `frs_break_find()` accepted `aoi` and never passed it to `.frs_break_find_table()`; BLK scoping has been in place since #81. Checked with `git show 667d0368^:R/frs_break.R`.
- *Against the code that generated the cached rds* (25b274d, 2026-03-19): that version applied `aoi` as a spatial filter. BLK scoping could also admit falls on a shared BLK outside the AOI.
  - For Byman-Ailport, `inst/extdata/falls.csv` (every `barrier_ind = TRUE` row from `falls_vw`) has **0** falls on mainstem BLK 360873822. The positive control, BLK 356364214, gets 1 hit.
  - Tributary BLKs sit entirely inside the network-subtracted AOI by construction.
  - So the set selected is the same.
- *For `pipeline_wsg.R`:* a BLK shared across watershed groups can bring in falls from outside the group. Only a downstream one can block, which is the right answer on the network and matches `frs_habitat()`'s own path.

**Is the vignette prose accurate?** For the code it shows, yes. "Locates barrier falls on the same streams and appends them to that breaks table" is true of `frs_feature_find(append = TRUE)`. G1 means that code does not run to completion. "Frs_break_find() with the attribute mode … at 100m intervals" is older wording that predates this diff; it is imprecise but not wrong in a way anyone would act on.

## Notes (pre-existing, not introduced by this diff)

**N1. The cached vignette data is falls-only, so regenerating it will move the figures.** `byman_ailport_habitat.rds$breaks_access_sf` holds exactly the 4 `barrier_ind = TRUE` falls and **no gradient barriers**, even though 624 cached segments have gradient > 0.15. In the code of that time, the falls call passed `append = TRUE` with the default `overwrite = TRUE`, and `frs_break_find()` dropped `to` whenever `overwrite` was TRUE, so the gradient breaks were deleted. The prose, before and after this diff, says both sources feed the table, but the plot-access figure and its counts (2948 accessible / 1879 not) reflect falls only. Once G1 is fixed and `data-raw/vignette_habitat_pipeline.R` is re-run, the accessible counts will fall. That is the correction, not a regression.

**N2. The `frs_col_join()` subquery example now runs, but writes a text column.** Before F3 the example died with a syntax error (`(...) sub _src`). Now it succeeds and adds `upstream_area_ha` as **text**:
- For a subquery `from`, `frs_col_join()` defaults `col_types` to `"text"` (code comment, R/frs_col_join.R:85).
- Postgres I/O conversion to a string type is an assignment cast, so the `UPDATE` does not complain.

The roxygen for `from` and the example say nothing about this. A user who follows the example gets a character column, and string comparisons downstream. This is low severity and was a design choice before this diff, but F3 is what makes the example reachable. Two remedies: document it beside the example, or infer types for subqueries with `SELECT * FROM <from> _src LIMIT 0` (the column classes, or `pg_typeof`).

## Verified clean

- **`frs_break()`:** forwards only arguments that `frs_break_find()` / `frs_break_validate()` / `frs_break_apply()` accept.
- **`@inheritParams frs_break_find`:** fills only the formals `frs_break` still has.
- **`frs_habitat_access()`:** every argument it passes is a formal of `frs_feature_find()`. `overwrite = FALSE, append = TRUE` keeps the gradient rows; `frs_feature_find` drops only when `overwrite && !append`.
- **Types:** INSERT by named columns into the threshold-mode table (`numeric` measure, text label) and the multiclass table (extra `gradient_class`) both cast cleanly.
- **New formals() tests:** fail against the old shapes. The old `frs_break` passed `points_table`/`points`/`where`/`aoi`, which are not formals. The old `frs_habitat_access` produced a call order of three `frs_break_find` calls, which fails `expect_equal`.
  - Ran with `test_file()`: test-frs_break.R 23/0 fail/0 error; test-frs_habitat.R 27/0/0; test-frs_col_join.R 7/0/0.
- **F1 `gate` doc:** matches the SQL. In `frs_habitat_classify` a segment is accessible iff there is no blocking break downstream on the same BLK (`b.drm <= s.drm`) or across BLKs (`fwa_upstream(b, s)`). So segments upstream of a blocking break are inaccessible.
- **`measure_precision` doc on `frs_break_apply`:** matches `SELECT DISTINCT blue_line_key, round(drm::numeric, mp)`.
- **`frs_habitat`:** the `@inheritParams` (`gate`, `label_block`, `measure_precision`) correspond to real formals that are passed straight through.
- **F3 alias removal:** correct. The SQL is `FROM %s _src`, so `(...) sub _src` was a syntax error.
- **`.Rbuildignore`:** `^\.lintr$` and `^docker$`. Nothing in R/, tests/ or vignettes/ reads `docker/`. The patterns are anchored and carry no comment lines.
- **ASCII `stop()`:** the test matches the prefix "No drainage closure found", which is unaffected.
- **Suggests `tibble`:** covers `tibble::tibble()` in test-frs_network_features.R.
- **Sweep:** no remaining caller of the removed `frs_break` args in fresh or ../link (R/, tests/, data-raw/).
