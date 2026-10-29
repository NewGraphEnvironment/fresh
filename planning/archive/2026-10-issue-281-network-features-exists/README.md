# #281: `frs_network_features(result = "exists")`

## Outcome

Added `result = c("ids", "exists")` to `frs_network_features()`. `"exists"` returns the segments that have any feature at the requested position, one row each with `has_features = TRUE`, the same rows the array walk returns, so link's `id %in% result$id` switches by one argument. It is the array walk's own join reduced to `SELECT DISTINCT`, and the FROM, predicate and `aoi` filter are built once (`walk_from`) for both results, which keeps the `"ids"` SQL byte-identical to 0.46.0. The output shape (matching rows only) was decided at the plan gate. A segment whose only features have NULL ids counts (plan review B2), so the result is the array walk's row set, not `lengths > 0`. Four `/code-check` rounds ended by an enumeration of 61 derived-twice pairs. They found, in order: a measurement digest that let Postgres prune the arrays it claimed to time; prose figures derived by hand from the log; a second hand-written copy of the predicate that mocked tests could not pin; a `@return` paragraph that had never landed; and one double-rounded table cell. The shared cause: a check that reads only what two derivations share agrees whatever the differing part does.

## Measurement

Local `docker/` fwapg (PostgreSQL 17.5), link's `fresh_default` natural barrier views (CH, BT, ST access), `include_equivalents = TRUE`, four groups.

- **Form:** the join, not a correlated `EXISTS`. `EXISTS` drives from the segments and tests each one against a materialized feature list (CHWK CH: about 5,200 rows per segment, no index). It was 1.1× (SALR) to 15× (LFRA BT) slower than the join in the same batch. Against the unprefiltered view it hit a 5-minute cap on CHWK CH, where the join takes 2.6 s.
- **Saving:** end to end through the function, exists is 1.00× (SALR) to 1.24× (SETN) faster; SETN CH goes from 50.2 s to 40.6 s. At the SQL level with the arrays built, it is 0.99× to 1.18×.
- **Where the time goes:** in SETN CH the join produces 4,829,028 pairs in 37.9 s of 45.3 s, and the sort spills 538,912 kB. That reproduces link#394's 4.83 M pairs and 526 MiB, but the spill is the smaller part. The issue expected SETN to move; it moved about 20%.
- **Wrong turn kept:** the first SQL-level `ids` timings digested only the id column, so the planner replaced `array_agg` with `NULL` and those rows timed the walk without its arrays (code-check round 1, confirmed with `EXPLAIN (VERBOSE)`). They are kept in the log and labelled. The re-timed `ids_arrays` batch replaces them in every figure.
- **Probe that differs:** the SETN array walk took about 50 s here, not the more than 10 minutes in the issue's cancelled probe (not investigated).
- Durable verdict: `research/fwa_downstream_walk.md`, "Existence walks".

## Evidence

`data-raw/logs/network_features_exists_281/` (walks.tsv and the batch descriptions in its README; `plans/*.json`), from `data-raw/network_features_exists.R`.

## Owed

- link#394 lever 1: switch the natural-barrier walks to `result = "exists"` in link, which needs a fresh floor bump and keeps the array form for any table link also uses as a source (its walk cache is per table). A link PR, not this one.

Closed by: PR (to be opened from branch `281-frs-network-features-an-existence-mode-t`)
