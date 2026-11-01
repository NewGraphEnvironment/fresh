# Code-check review, round 1 (#281, branch 281-frs-network-features-an-existence-mode-t)

## Checklist read

- `code-check-infra.md`: in full.
- `code-check.md`: the prose of all 14 H3s under `## Mechanisms`, with the table rows skipped. None of the "Rules that stand alone" or Security headings name anything this diff uses.
- `code-check-r.md`: 18 sections read: Postgres row order; `sprintf("%g")` in SQL; `information_schema` lookup; Rscript reads a script as it runs; `data-raw/` must load the source tree; `lintr` and the installed package; Tests that silently do not run; testthat counts errors under `error`; `skip_if_not()` scope; `expect_gt()` takes no `info`; a driver's value is not a base type; `data.frame()` recycling against zero length; `function(...)` mocks; `R CMD check` runs against the installed package; `pkg::` in tests; `tryCatch()` nesting; `tryCatch(warning = )`; `::text` spelling. 93 not read.
- `code-check-spatial.md`: 3 read (`st_read()` partial-read warning; sf geometry-column name validation; `summarise()` on sf). The rest not read, since the diff does no spatial work beyond `frs_db_query()` = `sf::st_read()` on DBI.
- `code-check-shell.md`: 2 read (`Rscript -e` and `--args`; shadowed verification commands). The rest not read, since the diff has no shell code.

Mocked suite: `devtools::test(filter = "frs_network_features$")` gives FAIL 0, PASS 140. Nothing was run against a database. I recomputed every number in the log README, NEWS and research from `walks.tsv` and the two plan JSONs.

## Findings

- **[fragile]** `data-raw/network_features_exists.R:162-166` (`digest_sql`), and the claims built on it: `data-raw/logs/network_features_exists_281/README.md:14,63-64` and `research/fwa_downstream_walk.md:114-115`.
  - **The SQL-level `ids` timings never build the arrays.** `digest_sql()` wraps the array walk as `SELECT count(*), md5(string_agg(id_segment::text …)) FROM (<ids walk>) x`, and that reads only `id_segment`.
  - PostgreSQL's `remove_unused_subquery_outputs()` replaces an output column the outer query does not reference with a NULL constant. I checked it in REL_17_5 `src/backend/optimizer/path/allpaths.c`. Its conditions all hold for `feature_ids`:
    - the subquery has no set operation and no plain DISTINCT;
    - the column is not resjunk and has no sortgroupref (the GROUP BY is on the id only);
    - it contains no SRF and no volatile function.
  - So `array_agg(d.feature_id) FILTER (…)` is planned as `NULL::text[]`. The inner `ORDER BY` and the `GROUP BY` still run, because their keys carry sortgroupref.
  - The `ids` column of the README table is therefore join + sort + group, without the aggregation. That contradicts:
    - README line 14: "`ids`: the array walk as the function sends it" (true of the SQL text, not of what executes);
    - README lines 63-64: "What the exists mode drops is the array aggregation … up to 15% of the array walk's SQL time" (the 15% contains no array aggregation);
    - research line 114: SETN CH "takes … 47 s as arrays".
  - It also shifts the SQL-level `EXISTS`-vs-arrays ratios quoted in NEWS and research ("1.1× to 13×"), because their denominator is the pruned walk.
  - The `fn_ids` / `fn_exists` end-to-end numbers do build the arrays, since they are returned to R. So NEWS's headline "1.00× to 1.24×" and "41 s rather than 50 s" stand.
  - #272's `digest_sql` in `data-raw/network_features_prefilter.R` hashed `feature_ids::text`, which forces the aggregate. This script dropped that. Fixes, either:
    - make the digest read the arrays (for example `sum(cardinality(feature_ids))`, or the #272 form);
    - or reword the SQL-level claims as "join + sort + group".
  - Confirm with `EXPLAIN (VERBOSE)` of `digest_sql(<ids sql>)`: the aggregate's Output shows the NULL constant.

- **[fragile / prose]** `data-raw/logs/network_features_exists_281/README.md:36`: "Seconds, mean of two runs." For SALR, CHWK and LFRA, the `ids` column is the mean of **four** runs from two batches, the 00:35-00:46 batch and the 01:00 batch. CHWK CH 2.82 = mean(3.068, 2.740, 2.711, 2.747). No pair of those runs gives 2.82: the first batch gives 2.90, the second 2.73, and all six runs give 2.80.
  - The `ids / exists` ratio therefore divides that four-run mean, including a cold first run (3.068), by `exists` runs from the 01:00 batch only. Against the `ids` runs from the batch the `exists` runs are in, CHWK CH is 1.08×, not the 1.11× printed. LFRA CH is 1.15×, not 1.16×.

- **[prose]** `data-raw/logs/network_features_exists_281/README.md:53`: "`distinct_sql` and `exists` … time within 0.1 s of each other." The log disagrees:
  - LFRA CH: 9.762 vs 9.631 s (0.13 s);
  - SETN CH: 40.524 vs 40.355 s (0.17 s);
  - CHWK CH: 2.635 vs 2.534 s (0.10 s).

- **[prose]** `data-raw/logs/network_features_exists_281/README.md:64-65`: "up to 19% end to end (SETN)". SETN BT is 1 - 17.133/21.306 = 19.6%, which rounds to 20% and matches the table's 1.24×.

- **[prose]** `research/fwa_downstream_walk.md:107-108`: "11.4 s against 2.8 s for the join". These are `EXPLAIN (ANALYZE)` times from `plans/`, and the research sentence does not say so. Per-row instrumentation over the semi-join's 74.8 M join-filter evaluations roughly doubles the `EXISTS` time. The timed runs in `walks.tsv` are 6.10 s for `exists_sql` against 2.63 s for `distinct_sql` (2.53 s for `exists`), so the timed gap is about 2.3×, not about 4×. The log README attributes the 11.4 s to "the CHWK CH plans", which is accurate. The research sentence, which sits beside timed figures, does not.

## Not findings (checked)

- `R/frs_network_features.R` exists path:
  - it uses the same predicate, column substitution, `aoi_filter` and scoped temp table + prefilter as the array walk;
  - `on.exit` drops the temp table on the early `return()`;
  - `rep(TRUE, nrow(res))` on a zero-row `data.frame` is safe (the mocked test covers it);
  - the `"ids"` SQL is byte-identical to 0.46.0.
- Every number in the README table, the NEWS bullets and the research section, other than those above, reproduces from `walks.tsv`. That covers the segment counts, the fn ratios 1.00× to 1.24×, the EXISTS ratios 1.08× to 13.18×, the two `others_active` rows, both timeouts at 01:21 and 01:26, the 00:35-01:26 window, and one digest per walk across all forms.
