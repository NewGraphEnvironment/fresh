# Findings — frs_network_features(): an existence mode (#281)

## Issue context

**If we do it:** a caller that only needs to know whether any feature lies downstream of each segment gets that answer without building and sorting every (segment, feature) pair, and keeps #272's temp table and prefilter. **If we never do:** callers build full arrays and throw them away; in groups where the pairs are many, that build is the walk's cost and #272's prefilter barely moves it.

## Problem

`frs_network_features()` returns, per segment, the array of every feature downstream (or upstream). Some callers reduce that array to one boolean per segment. NewGraphEnvironment/link#394 measured the cost of building what is thrown away: in SETN the CH walk produces 4.83 M (segment, feature) pairs and spills a 526 MiB sort to disk, and #272's prefilter makes that group's walks only 1.2× faster, because the time is in the output, not the probing.

## Proposed

An existence mode on `frs_network_features()`, for example `result = c("ids", "exists")`:

- `"exists"` returns one row per AOI segment with a logical `has_features` (or only the segments that have one, matching the current inner-join shape; to decide in the plan).
- It uses the same `fwa_downstream()` / `fwa_upstream()` predicate, and on the scoped downstream path the same temp table and prefilter, so its booleans equal `lengths(feature_ids) > 0` from the array mode by construction.
- No sort and no `array_agg`; `EXISTS` (or a semi-join) can stop at the first match per segment.

## How to measure

Against the array mode on SALR, CHWK, SETN and LFRA with link's natural barrier views: identical booleans per segment, and the time of each. SETN is the group that should move.

Relates to NewGraphEnvironment/link#394 (lever 1) and NewGraphEnvironment/link#377.


## Found while exploring (2026-10-28, not yet a plan)

- **How link uses the result** (`R/lnk_pipeline_access.R`, v0.69.3): `has_barriers_<sp>_dnstr` and `has_barriers_<src>_dnstr` are `out$id %in% result$id`; zero rows means NA or FALSE by species presence; link renames column 2 (`names(df)[2] <- ...`). So an exists result that keeps one row per segment with a feature, plus a second column, lets link switch by adding one argument. Walks that still need arrays: anthropogenic and dams (`dam_dnstr_ind` reads the first element) and the upstream observations walk (species codes). link caches walks per table across its per-species and per-source loops, so a table used in both roles needs the array form.
- **The SQL** (`R/frs_network_features.R`, 0.46.0): one `array_agg ... ORDER BY ... GROUP BY` shape; the scoped downstream path (#272's temp table and prefilter) only changes the `FROM` sources, so a second shape can reuse it.
- **Open for the plan:** `EXISTS` (stops at the first match per segment, but drives from the segments) vs `SELECT DISTINCT` over the same join (keeps #272's feature-driven plan, no sort of pairs). Measure both on smaller groups (SALR, CHWK, LFRA) before SETN: SETN has 188,554 segments, and a probe of the array form alone on its CH view ran past 10 minutes and was cancelled.
- **Before any timing:** check `pg_stat_activity` for other active client backends; the cancelled probe ran beside another session's query.


## Errors Encountered

| Error | Resolution |
|-------|------------|
