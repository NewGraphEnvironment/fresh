# network_features_exists_281

Timings of `frs_network_features(direction = "downstream", aoi = <group>)` with and without
the arrays, for fresh#281. Produced by `data-raw/network_features_exists.R` on 2026-10-29
(00:35-01:26 UTC; `measured_utc` is each run's end) on the local `docker/` fwapg,
PostgreSQL 17.5.

- **Shape:** `segments = fresh_default.streams` with `aoi`, as link calls it. `features` is
  one of link's natural barrier views per barrier-set shape: `barriers_ch_access`,
  `barriers_bt_access`, `barriers_st_access`. `include_equivalents = TRUE`.
- **SQL forms**, all on one indexed, analyzed temp table of the group built by
  `.frs_walk_scope()`, and (except `exists_base_sql`) the features cut by
  `.frs_walk_prefilter()`:
  - `ids`: the array walk as the function sends it.
  - `exists_sql`: `SELECT DISTINCT a.id … WHERE EXISTS (…)` against the prefiltered features.
  - `distinct_sql`: `SELECT DISTINCT a.id` over the same join.
  - `exists`: what `result = "exists"` sends, captured from the function (the `distinct_sql`
    form).
  - `exists_base_sql`: the correlated `EXISTS` against the view itself, unprefiltered.
- **End to end:** `fn_ids` and `fn_exists` call the function itself. They include its own temp
  table, the walk, the transfer, and for `ids` the R parse of every array. This is the cost
  link sees.
- **Order:** the forms run, then the same forms in reverse, per walk. The statement cap was 30
  minutes, and 5 minutes for the `exists_base_sql` run. Nothing hit the 30-minute cap.
- **Digest:** `d_ids` is the md5 of the comma-joined sorted segment ids a form returns. For
  `ids` that is the segments with a row in the array result, which is what link reads
  (`id %in% result$id`). `fn_*` digests the ids returned to R, with the same md5 computed in
  the database. All twelve walks agree across every form. `segments_out` is the count.
- **Load:** `others_active` is 0 on every row except two (one other client backend):
  SETN CH `fn_exists` rep 3 and SETN BT `fn_ids` rep 4. Neither differs much from its pair.
- `plans/`: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` of `exists_sql` and `distinct_sql` on
  CHWK CH.

## Results

Seconds, mean of two runs.

| group (segments with a barrier downstream, CH) | view | ids | exists_sql | exists | ids / exists | fn_ids | fn_exists | fn ratio |
|---|---|---|---|---|---|---|---|---|
| SALR (1,343) | CH | 1.87 | 2.17 | 1.85 | 1.01× | 1.94 | 1.94 | 1.00× |
| | BT | 0.71 | 0.77 | 0.71 | 0.99× | 0.81 | 0.81 | 1.00× |
| | ST | 1.23 | 1.38 | 1.22 | 1.00× | 1.33 | 1.32 | 1.00× |
| CHWK (11,301) | CH | 2.82 | 6.10 | 2.53 | 1.11× | 3.02 | 2.73 | 1.11× |
| | BT | 1.07 | 4.01 | 1.01 | 1.06× | 1.29 | 1.17 | 1.10× |
| | ST | 1.84 | 5.16 | 1.73 | 1.06× | 2.10 | 1.94 | 1.08× |
| LFRA (45,994) | CH | 11.19 | 96.56 | 9.63 | 1.16× | 12.37 | 10.15 | 1.22× |
| | BT | 4.47 | 58.91 | 3.99 | 1.12× | 5.43 | 4.56 | 1.19× |
| | ST | 7.52 | 79.63 | 6.63 | 1.14× | 8.71 | 7.36 | 1.18× |
| SETN (180,313) | CH | 47.27 | | 40.35 | 1.17× | 50.21 | 40.64 | 1.24× |
| | BT | 17.85 | | 16.31 | 1.09× | 21.31 | 17.13 | 1.24× |
| | ST | 30.76 | | 27.44 | 1.12× | 35.42 | 29.10 | 1.22× |

`distinct_sql` and `exists` are the same SQL and time within 0.1 s of each other. The
correlated `EXISTS` is 1.1× (SALR) to 13× (LFRA BT) slower than the array walk and was not run in SETN.
`exists_base_sql` on CHWK CH hit the 5-minute cap on both runs (01:21 and 01:26 UTC), where the
array walk took 2.8 s.

**Why `EXISTS` loses.** In the CHWK CH plans, `exists_sql` becomes a nested-loop semi-join. It
scans the 14,347 segments and tests each against the materialized prefiltered features,
about 5,200 rows a segment, with no index (11.4 s). `distinct_sql` drives from the 8,585
admitted features and probes the temp table's indexes: 161,974 pairs in 2.8 s, then a hash
aggregate to 11,301 ids. Nearly all of that time is the join itself, which the array walk
runs too. What the exists mode drops is the array aggregation, its sort, and, end to end, the
transfer and R parse of the arrays: up to 15% of the array walk's SQL time and up to 19% end
to end (SETN). Whether the SETN array walk spills its sort to disk here, as link#394 measured
(526 MiB), was not checked: by then another client was walking the same database.

`walks.tsv` columns: `wsg`, `features`, `form`, `rep`, `segments_out`, `seconds`, `timed_out`,
`d_ids`, `others_active`, `measured_utc`.
