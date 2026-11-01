## Checklist read

All five FULL TEXT files are over 40,000 bytes, so none was read in full.
- code-check.md: the prose of all 14 H3s under `## Mechanisms` (table rows and evidence blocks skipped). No other headings read.
- code-check-r.md: read "Postgres row order is never fixed unless the query fixes it…", "A database driver's value is not a base R type — and it fails twice", "A value compared as `::text` in SQL has PostgreSQL's spelling, not R's", "Tests that silently do not run", "`expect_gt()` and friends take no `info` argument", "A `function(...)` mock hides arguments the real callee no longer accepts", "`sort()` and `order()` collate by `LC_COLLATE`…", "Under `R CMD check`, tests run from a temp dir against the INSTALLED package", "`expect_false(identical(x, y))` cannot fail when the two are different types" (9 read; the rest not read: about 180 headings).
- code-check-infra.md: read "A SQL function test that cannot fail: pruned columns and a function in `FROM`" and "Function-as-join-predicate: index visibility depends on inlineability" (2 read, about 38 not).
- code-check-shell.md, code-check-spatial.md: no heading names a tool or shape this diff uses; none read.

## What was checked

- Ran both test files from a worktree at b3557d0 against local fwapg (NOT_CRAN=true): mock file 218 pass / 0 fail / 0 error; local file 3 tests, 0 fail / 0 error (distinct test 18 pass).
- Probe with the consumer's shape (text `species_code`, varchar, ~25 % NULL ids) on SKGT, upstream (unscoped) and downstream (scoped temp-table path): `"distinct"` returns the same segment set as `"ids"`, and each segment's vector equals `sort(unique())` of the `"ids"` vector, including the segments whose only features have NULL ids (empty vector in both; 215 upstream, 28 downstream). Matches the documented contract.
- Mutation: dropping `DISTINCT` from the aggregate reddens the local parity test (3 failures) and the mock SQL test (4 failures), so both guards fire.
- `walk_from` shared with `"ids"`/`"exists"`; the scoped path's `on.exit` DROP fires on the new early `return()`; zero-row result handled as in `"ids"`; row order of the result is unordered as in `"ids"` and the consumer keys by segment id (`setNames`), so nothing reads it.

## Clean
No issues found.

Note, not a finding: the roxygen sentence "Only distinct pairs leave the server, so it stays cheap where every feature is reached by many segments" names the wrong condition for the saving. Fewer rows leave the server only where one segment reaches many features sharing an id (many records of one species); with a unique `feature_id_col` the output is the same size as `"ids"`. It changes no behaviour.
