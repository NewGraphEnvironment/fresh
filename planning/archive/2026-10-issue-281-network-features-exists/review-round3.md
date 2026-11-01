# Code-check round 3 (#281), whole branch

## Checklist read

- `code-check-infra.md`: in full.
- `code-check.md`: the prose of all 14 H3s under `## Mechanisms`, table rows skipped. No other sections (`## Rules that stand alone`, Security, Spreadsheets) read beyond their index lines; none applies to this diff.
- `code-check-r.md` (178 KB): read in full 15 sections: "A `data-raw/` script must load the source tree", "`lintr` also resolves against the installed package", "Tests that silently do not run", "testthat counts an uncaught error under `error`", "A `skip_if_not()` skips only its own `test_that()` block", "`expect_gt()` and friends take no `info` argument", "A database driver's value is not a base R type", "Under `R CMD check`, tests run from a temp dir", "`data.frame()` recycles a scalar against a zero-length column", "Postgres row order is never fixed", "`sprintf("%g", x)` writes `Inf`", "An `information_schema` lookup", "Rscript reads a script as it runs", "testthat 3e `expect_message()` returns the condition", "A `function(...)` mock hides arguments". The other headings (about 105) were read only as index lines.
- `code-check-shell.md` (125 KB): index only. The diff has no shell code beyond `Rscript` usage lines, and no heading's index line names anything it uses. 0 sections read.
- `code-check-spatial.md` (156 KB): index only. The only spatial call is `frs_db_query()` = `sf::st_read()`, and no heading covers the DBI read path. 0 sections read. I checked `sf:::st_read.DBIObject` directly instead (see finding 4).

## The mechanism

Rounds 1 and 2 found one shape. **The check reads only what the two sides share, so it agrees whatever the part that differs does.**

- Round 1: the timing digest read the id column, which both the array form and the exists form produce. It did not read the arrays, the only thing that separates them, so Postgres pruned them.
- Rounds 1 and 2, prose: figures were a second, hand-made derivation of `walks.tsv`. Summaries compressed per-walk numbers into per-group claims, and agreed with the log only where the two happened to coincide.

The same shape is in the code. `result = "exists"` carries a **second hand-written copy of the array walk's `fwa_<dir>()` predicate**, with renumbered `sprintf` slots (`%5$s`, `%7$s` to `%10$s` against the array walk's `%6$s`, `%8$s` to `%11$s`). The mocked assertions on that copy read only what every wiring of it shares: the function name, `SELECT DISTINCT`, and a boolean literal of either value. Finding 1 is that instance.

## Findings

- **[fragile] R/frs_network_features.R:308-323 and tests/testthat/test-frs_network_features.R:707-719.** The exists predicate's argument wiring is untested by anything that runs in CI. The mocked test asserts `expect_match(q, "true, 1|false, 1")`, which accepts either value. Nothing checks argument order. I ran mutations in a copy (`r3mut/`, `testthat::test_file`, failed and error counted together):
  - m1: `%5$s, 1` becomes `false, 1`, so `include_equivalents` is ignored.
  - m2: segment wscode and localcode swapped.
  - m3: segment and feature argument blocks swapped, so the relation runs backwards.
  - m4: feature side reads the segment code columns.

  All four leave the mocked file green: 0 failed, 0 errors, 36 blocks. The positive control is the same `false, 1` mutation on the array walk (`%6$s`). It is caught by "include_equivalents = TRUE produces 'true' in SQL".

  m1 to m3 return a wrong segment set with no error, and link calls with `include_equivalents = TRUE`. m4 fails loudly wherever the names differ. The only cover for m1 to m3 is the local-fwapg test, which never runs in CI (`code-check-r.md`, "Tests that silently do not run": give it a mock-based twin). Whether that test even sees m1 is unmeasured, since I may not run queries. It would need an SKGT segment whose only downstream feature is an equivalent at its own position.

  Fix it in one of two ways. Build the `ON` clause once and splice it into both SQL strings, so there is one copy. Or, in the mocked test, extract the `ON (...)` clause from the exists SQL and the array SQL and `expect_identical()` them, for `include_equivalents` TRUE and FALSE and with non-default `*_wscode_col`/`*_localcode_col`. Restore m1 to m3 to prove it.

- **[prose] data-raw/network_features_exists.R:49-50.** The script header says "NF281_VIEWS, NF281_FORMS, NF281_OUT and NF281_TIMEOUT_MS narrow a smoke run and keep it out of the log." Only `NF281_OUT` moves the output (lines 73, 223). The other three still append to `walks.tsv`. The log contradicts the header:
  - batches 2 to 4 ran with `NF281_FORMS` and are in `walks.tsv`;
  - batch 3 also ran with a 5-minute `NF281_TIMEOUT_MS`, and its rows are there too;
  - the header's own Usage lines 47-48 use `NF281_FORMS` for real runs.

  A smoke run that trusts the header writes into the evidence log.

- **[prose] data-raw/logs/network_features_exists_281/README.md:35.** "The statement cap was 30 minutes, which nothing hit." Batch 3 ran under a 5-minute cap (README line 32), and `walks.tsv` has CHWK CH `exists_base_sql` reps 2 and 3 with `timed_out = TRUE`. The 30-minute cap applies to batches 1, 2 and 4 only.

- **[prose] R/frs_network_features.R:117 (man `\value`).** The branch rewrote `@return` as "With `result = "ids"`, a tibble with two columns:" and gave no return for `"exists"`. The `has_features` column, and the absence of segments with no features, appear only in NEWS.

  The rewritten sentence also keeps "tibble", which the code contradicts. `frs_db_query()` is `sf::st_read()`, and for a query with no geometry `sf:::st_read.DBIObject` returns the plain `data.frame` from `dbGetQuery()`, because `as_tibble = FALSE`. The branch's own test comment (test-frs_network_features.R:755) says "a data.frame, as sf::st_read() returns". The word predates the branch, but this sentence was edited on it.

## Mechanism sweep: places it reaches, checked, no finding

- **Timing digest** (`digest_sql`). The exists, `distinct_sql` and `exists_sql` forms output only the id, so reading the id reads everything they produce. `ids_arrays` reads `cardinality(feature_ids)`. The old `ids` rows are labelled. OK.
- **End-to-end `fn_*` digest.** The function parses every array in R before returning, so `fn_ids` times the arrays. The md5 is built in R and computed in the database independently of `digest_sql`, and it matches the SQL digests for all 12 walks. OK.
- **EXPLAIN mode.** It explains `walk_sql()`, not the digested query that was timed. The three committed plans are unaffected: their top-level outputs equal what was timed. An EXPLAIN of form `ids` would show arrays that the timed `ids` rows never built, but none is committed or cited. OK.
- **`exists` against `distinct_sql`.** Their digests agree by construction, since they are the same SQL, and the README says so ("the `distinct_sql` form"). OK.
- **Local test oracle.** `result = "ids"` shares the scope, the prefilter and the `aoi` filter with exists, so the test checks `DISTINCT` against `GROUP BY` plus the column wiring. That is the stated claim, and the dup-segments and NULL-id tables make the two forms distinguishable (parent verified the `DISTINCT` mutation).
  - The comment "so through both prefilter arms" holds at the pair level (the #272 test asserts it). The test does not show that the arms change which segments are returned.
  - That leaves no hole, because `from_features` is a single variable shared by both forms, and the mocked test pins the prefilter text in the exists SQL.
- **Mocked "keeps the scoped walk".**
  - `norm(ex) == norm(ids)` holds by construction, since the DDL is built before the branch.
  - The prefilter oracle is the helper itself, called with hardcoded arguments. That checks the wiring, which is the claim.
  - `expect_no_match(..., "fresh\\.streams")` catches a bypass of the temp table.
- **"ids sends the same walk as the default".** Two calls through one path. The test cannot detect a change to the ids SQL, so NEWS's "same SQL as 0.46.0" rests on the parent's byte-compare and on the pre-existing ids tests, not on this test. The test name claims only default against explicit `"ids"`. OK.
- **Has-features test.** It fails on `has_features <- TRUE` (parent verified) and passes on correct code. OK.
- **Prose figures.** I recomputed every figure in NEWS 0.47.0, the README's Results table and paragraphs, and the research "Existence walks" section from `walks.tsv` (batch means) and the three plan JSONs. All match except README:35 above. They include:
  - 1.00× to 1.24× end to end;
  - SETN CH 50.21 s to 40.64 s;
  - SQL ratio 0.99× to 1.18×, up to 15.0% (SQL) and 19.6% (end to end) saved;
  - EXISTS 1.09× to 14.67× slower;
  - 5,216 rows per loop, 74.8 M filtered;
  - 11.42 s and 2.83 s (join node) under EXPLAIN ANALYZE, 6.1 s and 2.6 s timed;
  - 14,347 segments and 8,585 features;
  - 37.9 s of 45.3 s;
  - 538,912 kB = 526.3 MiB, 4,829,028 pairs;
  - 12 walks with one digest each;
  - `others_active` non-zero on exactly 2 rows.

  "The saving in seconds grows with the number of segments reached" holds per walk; the three SALR walks sit at 0.00 ± 0.01 s. "Rising from group to group" holds by group.
- **Planner-dependent wording (caveat, not a finding).** "No (segment, feature) pair is sorted" (roxygen, NEWS) describes what the SQL asks for. The planner may still implement `DISTINCT` as a Sort plus Unique over the join rows when it estimates the hash table won't fit in `hash_mem`. The CHWK plan used a hash aggregate. SETN's exists timing (38.3 s against the 37.9 s join) is consistent with no sort on this host, which is tuned with a large `work_mem`. A default-configured server is unmeasured.

/Users/airvine/Projects/repo/fresh/planning/active/review-round3.md
