# Review: fresh#284 `result = "distinct"`, round 3 (aabba77, b3557d0, 1b2d4bc over 7aedbe3)

## Checklist read
- code-check.md (334,881 bytes): the prose of every H3 under `## Mechanisms`, with `|` rows skipped. I read all fourteen up to "One fact derived twice", whose closing paragraph is truncated in my read. I read none of the 20 "Rules that stand alone" / Security / Spreadsheets headings: no tool or shape in this diff matches them.
- code-check-r.md (190,768 bytes): I read "A database driver's value is not a base R type — and it fails twice", "A value compared as `::text` in SQL has PostgreSQL's spelling, not R's", "Postgres row order is never fixed unless the query fixes it, so a pick, a float sum and a presence check can each depend on it", "`sort()` and `order()` collate by `LC_COLLATE`, so a canonical form is locale-dependent", "Tests that silently do not run", "A `function(...)` mock hides arguments the real callee no longer accepts" and "`as.integer("NaN")` is `0`, and `as.integer(NaN)` is `NA`". I did not read about 125 other headings.
- code-check-infra.md (41,794 bytes) and code-check-spatial.md (155,517 bytes): I read only the index lines. The diff uses no Docker, IaC or spatial tooling, and the one SQL-adjacent infra heading ("A SQL function test that cannot fail") does not apply, because no SQL function is defined here.
- code-check-shell.md (131,937 bytes): I read only the index lines, because the diff has no shell.

## Clean
No issues found.

## What I ran
- I made a worktree at 1b2d4bc (removed afterwards) and ran `NOT_CRAN=true` with `testthat::test_file()`. `test-frs_network_features.R` gave 218 passes and 0 failures, errors or skips. `test-frs_network_features-local.R` gave 66 passes and 0 failures, errors or skips, against the local fwapg.
- I ran a live probe on SKGT with a temp feature table: a text id column (`'BT'`, `'CO'` and NULL) and a `numeric` id column, both directions, with `aoi`.
  - In all four cases, `"distinct"` returns the same segment set and the same row count as `"ids"` (1,526 upstream, 6,711 downstream).
  - Each array equals `unique()` of the `"ids"` array as a set, with no duplicates.
  - Segments whose only features have a NULL id come back as `character(0)` in both modes: 271 and 271 upstream.
  - The numeric arrays are sorted numerically (…9, 10).
  - The segment id comes back as `integer64` in both modes.

## The mechanism behind rounds 1 and 2
**Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (its closing paragraph: terminate by enumerating every claim a diff makes about behaviour and executing each). Round 1 is also an instance of code-check-r.md "A value compared as `::text` in SQL has PostgreSQL's spelling, not R's".

Both earlier findings were claims about the result that were written down but never executed against the result itself:
- Round 1 was the test's oracle. It assumed R's spelling of a double, `as.character(360000000)` = `"3.6e+08"` (confirmed), is the array's text spelling.
- Round 2 was the roxygen's account of where the saving occurs.

The function was right both times. Below is every claim this diff makes about the result's form, with how I executed each one.

1. **Roxygen `@param result`, "each segment's feature IDs once each, sorted by the ID".** Holds: the probe found no duplicates, and the SQL is `array_agg(DISTINCT x ORDER BY x)`.
2. **Same place, "Only distinct pairs leave the server … with a unique `feature_id_col` it returns as much as `"ids"`".** Holds by construction. Both modes aggregate the same `walk_from` join, and neither the join nor the scoped prefilter (one `SELECT … FROM f WHERE … OR …`) can emit a feature twice for one segment.
3. **`@return`, "the same two columns as `"ids"` and the same rows".** Holds in the local test and in the probe. The rename via `names(res)[1]` is the same as in `"ids"`.
4. **`@return`, "sorted by the ID (in its SQL type's order, so numerically for a numeric ID)".** Holds on the probe's `numeric` column.
5. **`@return`, "the set `unique()` would give of the `"ids"` vector".** Holds on text, integer and numeric in the probe. A string-level difference is possible only where one value has two text spellings, such as `-0`/`0` in float8 or numeric `1.0`/`1.00`. That is immaterial for id columns, so it is not a finding.
6. **Code comment, "sorted by the id itself, so the order is a function of the data".** Holds, subject to the accepted collation note.
7. **Local test comment, "The fixture's feature ids are unique, so the id column here is blue_line_key, which many features share".** Holds. The fixture's ids are `linear_feature_id` and `-linear_feature_id` (disjoint), and the test's own `any(lengths(ids) > lengths(want))` premise passes in all three cases.
8. **Local test comment, "as.character() of a double prints … "3.6e+08", which the array's text never does".** Holds. R prints `3.6e+08`, and int4 or int8 array output has no exponent form.
9. **Local test, keys built by `as.character(<segment id>)` for the set comparison and for `names()`.** This is the same R-spelling mechanism, but harmless here. The segment id is `integer64` on both sides, so bit64's `as.character` prints full digits, and both sides use the same class and the same conversion.
10. **Mock test, `feature_ids = c("{BT,CO}", NA)` as plain character.** The live tests feed the driver's own array class through the same `lapply(.frs_parse_pg_array)` path, so the plain-character mock does not hide a type-only failure.

The mechanism reaches no other place in the diff. The function never converts an id between R and SQL spellings: it returns Postgres's array text, parsed. The consumer's own key, `as.character(sp_up[[segment_id_col]])` in link `R/lnk_pipeline_access.R`, is outside this diff.

/private/tmp/claude-501/-Users-airvine-Projects-repo-link/c3a2e038-8d96-43f5-8a70-4488060ea307/scratchpad/review-fresh284-round3.md
