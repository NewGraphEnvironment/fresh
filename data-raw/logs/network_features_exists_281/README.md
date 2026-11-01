# network_features_exists_281

Timings of `frs_network_features(direction = "downstream", aoi = <group>)` with and without
the arrays, for fresh#281. Produced by `data-raw/network_features_exists.R` on 2026-10-29
(00:35-01:58 UTC; `measured_utc` is each run's end) on the local `docker/` fwapg,
PostgreSQL 17.5.

- **Shape:** `segments = fresh_default.streams` with `aoi`, as link calls it. `features` is
  one of link's natural barrier views per barrier-set shape: `barriers_ch_access`,
  `barriers_bt_access`, `barriers_st_access`. `include_equivalents = TRUE`.
- **SQL forms**, all on one indexed, analyzed temp table of the group built by
  `.frs_walk_scope()`, and (except `exists_base_sql`) the features cut by
  `.frs_walk_prefilter()`:
  - `ids_arrays`: the array walk as the function sends it, digested with
    `sum(cardinality(feature_ids))` so the arrays are built. `n_pairs` is that sum.
  - `ids`: the same SQL with a digest that reads only the ids. Postgres then replaces the
    unread `array_agg` with `NULL::text[]` (`EXPLAIN (VERBOSE)` shows it), so these rows time
    the join, the sort and the `GROUP BY`, not the arrays. They are kept as run; no figure
    below uses them.
  - `exists_sql`: `SELECT DISTINCT a.id … WHERE EXISTS (…)` against the prefiltered features.
  - `distinct_sql`: `SELECT DISTINCT a.id` over the same join.
  - `exists`: what `result = "exists"` sends, captured from the function (the `distinct_sql`
    form).
  - `exists_base_sql`: the correlated `EXISTS` against the view itself, unprefiltered.
- **End to end:** `fn_ids` and `fn_exists` call the function itself. They include its own temp
  table, the walk, the transfer, and for `ids` the R parse of every array. This is the cost
  link sees.
- **Batches:** forms run, then the same forms in reverse, per walk.
  1. 00:35-00:46 `ids`, `exists_sql`, `distinct_sql` on SALR, CHWK, LFRA.
  2. 00:51-01:11 EXPLAIN on CHWK CH; `ids`, `distinct_sql`, `exists` on SETN; `ids`, `exists`
     on SALR, CHWK, LFRA; `fn_ids`, `fn_exists` on all four.
  3. 01:16-01:26 `ids`, `exists_base_sql` on CHWK CH (5-minute cap).
  4. 01:49-01:58 `ids_arrays`, `exists` on all four, then EXPLAIN of `ids_arrays` on SETN CH.

  The statement cap was 30 minutes in batches 1, 2 and 4, which nothing hit, and 5 minutes in
  batch 3, which both `exists_base_sql` runs hit.
- **Digest:** `d_ids` is the md5 of the comma-joined sorted segment ids a form returns. For
  the array forms that is the segments with a row in the array result, which is what link
  reads (`id %in% result$id`). `fn_*` digests the ids returned to R, with the same md5
  computed in the database. All twelve walks agree across every form and batch.
  `segments_out` is the count.
- **Load:** `others_active` is 0 on every row except two (one other client backend):
  SETN CH `fn_exists` rep 3 and SETN BT `fn_ids` rep 4. Neither differs much from its pair.
- `plans/`: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` of `exists_sql` and `distinct_sql` on
  CHWK CH, and of `ids_arrays` on SETN CH.

## Results

Seconds, mean of the two runs of each form within one batch. The SQL columns are batch 4, and
the `fn` columns are batch 2.

| group (segments reached, CH) | view | pairs | ids_arrays | exists | ratio | fn_ids | fn_exists | fn ratio |
|---|---|---|---|---|---|---|---|---|
| SALR (1,343) | CH | 5,144 | 1.86 | 1.85 | 1.00× | 1.94 | 1.94 | 1.00× |
| | BT | 1,025 | 0.71 | 0.71 | 1.00× | 0.81 | 0.81 | 1.00× |
| | ST | 2,513 | 1.21 | 1.22 | 0.99× | 1.32 | 1.32 | 1.00× |
| CHWK (11,301) | CH | 161,974 | 2.84 | 2.60 | 1.09× | 3.02 | 2.73 | 1.11× |
| | BT | 60,414 | 1.10 | 1.04 | 1.05× | 1.29 | 1.17 | 1.10× |
| | ST | 105,561 | 1.90 | 1.81 | 1.05× | 2.10 | 1.94 | 1.08× |
| LFRA (45,994) | CH | 1,171,394 | 11.26 | 9.62 | 1.17× | 12.37 | 10.15 | 1.22× |
| | BT | 464,715 | 4.46 | 3.99 | 1.12× | 5.43 | 4.56 | 1.19× |
| | ST | 799,789 | 7.60 | 6.63 | 1.15× | 8.71 | 7.36 | 1.18× |
| SETN (180,313) | CH | 4,829,028 | 45.01 | 38.27 | 1.18× | 50.21 | 40.64 | 1.24× |
| | BT | 1,665,803 | 17.37 | 15.64 | 1.11× | 21.31 | 17.13 | 1.24× |
| | ST | 3,076,678 | 29.93 | 26.17 | 1.14× | 35.42 | 29.10 | 1.22× |

The correlated `EXISTS` (`exists_sql`, batch 1) is 1.1× (SALR) to 15× (LFRA BT) slower than
the join (`distinct_sql`, same batch), and was not run in SETN. `exists_base_sql` on CHWK CH
hit the 5-minute cap on both runs (01:21 and 01:26 UTC), where the array walk took 2.8 s.

**Why `EXISTS` loses.** In the CHWK CH plans, `exists_sql` becomes a nested-loop semi-join. It
scans the 14,347 segments and tests each against the materialized prefiltered features,
about 5,200 rows a segment, with no index: 11.4 s under `EXPLAIN ANALYZE`, 6.1 s timed.
`distinct_sql` drives from the 8,585 admitted features and probes the temp table's indexes:
161,974 pairs in 2.8 s under `EXPLAIN ANALYZE`, 2.6 s timed, then a hash aggregate to 11,301
ids.

**Where the array walk's time goes.** In SETN CH the join produces the 4,829,028 pairs in
37.9 s of the 45.3 s `EXPLAIN ANALYZE`. The sort of the pairs then spills to disk
(external merge, 538,912 kB), which reproduces link#394's 4.83 M pairs and 526 MiB. The
exists mode runs the same join and drops the sort, the aggregation, and, end to end, the
transfer and R parse of the arrays. That saves up to 15% of the SQL time and up to 20% end
to end (SETN BT: 21.3 s to 17.1 s).

`walks.tsv` columns: `wsg`, `features`, `form`, `rep`, `segments_out`, `seconds`, `timed_out`,
`d_ids`, `others_active`, `measured_utc`, `n_pairs` (`ids_arrays` rows only; `NA` elsewhere,
added as a column after batches 1 to 3).
