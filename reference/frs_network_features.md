# Per-Segment Arrays of Features Relative to a Stream Network

For each row in a segments table, return an array of feature IDs from a
features table that lie at the requested relative position (downstream
of, or upstream of) that segment in the FWA stream network. The features
can be any point dataset snapped to FWA – barriers, crossings,
observations, water-quality stations, fish surveys, sediment-sample
points, weather stations – anything with
`(blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree)`
keys.

## Usage

``` r
frs_network_features(
  conn,
  segments,
  features,
  segment_id_col = "id_segment",
  feature_id_col,
  direction,
  aoi = NULL,
  include_equivalents = FALSE,
  segments_wscode_col = "wscode_ltree",
  segments_localcode_col = "localcode_ltree",
  features_wscode_col = "wscode_ltree",
  features_localcode_col = "localcode_ltree",
  result = c("ids", "exists", "distinct")
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object pointing at fwapg.

- segments:

  Character. Schema-qualified segments table. Must have
  `<segment_id_col>`, `blue_line_key`, `downstream_route_measure`,
  `wscode_ltree`, `localcode_ltree`, and `watershed_group_code` columns
  (the last only when filtering via `aoi`).

- features:

  Character. Schema-qualified features table. Must have
  `<feature_id_col>`, `blue_line_key`, `downstream_route_measure`,
  `wscode_ltree`, `localcode_ltree` columns.

- segment_id_col:

  Character. Default `"id_segment"`. The per-segment unique key column
  on the segments table.

- feature_id_col:

  Character. The unique-key column on the features table (e.g.
  `"barriers_pscis_id"`, `"observation_key"`, `"station_id"`).
  **Required – no default; caller passes the actual column name.**

- direction:

  Character. **Required – no default.** One of `"downstream"` or
  `"upstream"`. `"downstream"` returns features that lie below each
  segment (toward the river mouth). `"upstream"` returns features above
  each segment.

- aoi:

  Character. Optional area-of-interest filter on segments. Today only
  WSG codes (e.g. `"ADMS"`, `"BULK"`) are supported and filter
  `segments.watershed_group_code = aoi`. Polygon / ltree AOIs are
  forward-compat – they will route through `.frs_resolve_aoi()` when
  generalised. Default `NULL` processes every row in the segments table.
  With `direction = "downstream"`, an `aoi` also switches on the scoped
  walk, which needs a session that can create temp tables: see "Scoped
  downstream walks" below.

- include_equivalents:

  Logical. When `TRUE`, treats segments at the same
  `(blue_line_key, downstream_route_measure)` position as
  relative-direction matches of each other. Mirrors bcfishpass's
  `include_equivalents` arg. Default `FALSE`.

- segments_wscode_col:

  Character. Watershed-code column on the `segments` table. Default
  `"wscode_ltree"` matches `fresh.streams`, `bcfishpass.streams`,
  `bcfishpass.barriers_*`.

- segments_localcode_col:

  Character. Local-code column on `segments`. Default
  `"localcode_ltree"`.

- features_wscode_col:

  Character. Watershed-code column on the `features` table. Default
  `"wscode_ltree"`. Pass `"wscode"` when
  `features = "bcfishpass.observations"` (which uses unsuffixed column
  names) or any other FWA-snapped point dataset following the same
  convention.

- features_localcode_col:

  Character. Local-code column on `features`. Default
  `"localcode_ltree"`. See `features_wscode_col`.

- result:

  Character. `"ids"` (default) returns each segment's array of feature
  IDs. `"exists"` returns only whether a segment has any feature at the
  requested position, without building the arrays: the same walk
  (predicate, `aoi`, scoped downstream path) reduced to the distinct
  segment IDs it reaches, so no array is aggregated and the walk has no
  `ORDER BY`. Its segments are exactly the rows `"ids"` returns. Use it
  when the arrays would only be tested for presence
  (`id %in% result$id`). `"distinct"` returns each segment's feature IDs
  once each, sorted by the ID, from the same walk: the answer to which
  kinds of feature lie up or downstream when `feature_id_col` names a
  kind (a species code, say). Only distinct pairs leave the server, so
  it stays cheap where a segment reaches many features that share an ID
  (a main stem below thousands of records of a few species); with a
  unique `feature_id_col` it returns as much as `"ids"` (#284).

## Value

With `result = "ids"`, a data frame with two columns:

- `<segment_id_col>` – matches the input column name on segments.

- `feature_ids` – an R list-column of character vectors (one vector per
  row). The vectors carry the feature IDs aggregated from the requested
  direction, ordered by
  `(wscode_col DESC, localcode_col DESC, downstream_route_measure DESC, feature_id_col)`.
  The first three keys are `bcfishpass.load_dnstr`'s; the last breaks
  its ties (co-located features), so the order is a function of the data
  rather than the query plan when `feature_id_col` is unique. Segments
  with zero matches don't appear in the output (INNER JOIN). Postgres
  array literals are parsed to R character vectors via the internal
  `.frs_parse_pg_array()` helper – limited to unquoted-element arrays
  (the common case for FWA-snapped IDs).

With `result = "exists"`, a data frame with one row per distinct
`<segment_id_col>` that has at least one feature at the requested
position, and a logical `has_features` that is `TRUE` on every row.
Segments with none don't appear, as with `"ids"`. A feature counts
whatever its ID, so a segment whose only features have a NULL ID is a
row in both forms (an empty array under `"ids"`).

With `result = "distinct"`, the same two columns as `"ids"` and the same
rows, with each segment's IDs once each, sorted by the ID (in its SQL
type's order, so numerically for a numeric ID): the set
[`unique()`](https://rdrr.io/r/base/unique.html) would give of the
`"ids"` vector.

## Details

Mirrors `bcfishpass.load_dnstr_chunked` in
`bcfishpass/db/migrations/archive/v0.7.6/load_dnstr_chunked.sql` but
generalises to either direction. The SQL pattern joins via
`whse_basemapping.fwa_<direction>()` for cross-mainstem ltree
comparison, then `array_agg`s feature IDs grouped by segment ID.

With `result = "exists"` the same walk answers only whether each segment
has any such feature, returning the segments that do without building
their arrays (#281).

## Scoped downstream walks

With `direction = "downstream"` and an `aoi`, the walk is cut to what
`fwa_downstream()` can return before it runs. A feature can only lie
downstream of a segment when it is on the segment's blue line, or when
its watershed code is an ancestor of, or equal to, the segment's
(`fwa_downstream()`'s two criteria). The function therefore:

1.  copies the AOI's segments (the id, `blue_line_key`,
    `downstream_route_measure` and the two code columns) into a session
    temp table, with a btree index on `blue_line_key`, GiST indexes on
    both codes, and `ANALYZE`;

2.  admits only the features on one of those blue lines, or whose
    watershed code equals one of the segments' codes or one of their
    ancestors, through the feature table's own indexes;

3.  walks the temp table against the admitted features with the same
    `fwa_downstream()` predicate, and drops the temp table on exit.

The answer is the same as the unprefiltered join's: the admitted set
contains every feature either criterion can reach, whatever
`include_equivalents` is. What changes is the plan. Unscoped, the join
order depends on the tables: against a large feature table the planner
can probe the segments once per feature in the whole table, and with a
province-wide segments table it can leave the segment-driven plan
altogether. Scoped, it probes a small indexed table once per admitted
feature (#272).

**Session requirement.** A scoped call runs several statements that must
reach one backend, and one of them creates a temp table. In a read-only
transaction or on a hot standby the call stops there, with an error
naming the cause. A transaction-pooling connection pooler (pgbouncer
`pool_mode = transaction`) can send the statements to different
backends. The call then fails, either while building the table (the same
error) or at the walk, because the temp table is not on the walk's
backend, and the table can be left on the backend that made it. Use a
direct connection or session pooling. If the call is inside a
transaction that the walk aborts, the temp table's `DROP` fails too and
the table lasts until that transaction is rolled back.

`aoi = NULL` and `direction = "upstream"` run the unprefiltered walk and
create nothing. A caller holding a segments table already cut to one
watershed group should still pass `aoi` to get the scoped walk.

## See also

Other network:
[`frs_candidates_pick()`](https://newgraphenvironment.github.io/fresh/reference/frs_candidates_pick.md),
[`frs_point_match()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_match.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Barriers downstream of each segment (bcfishpass-parity use case)
dnstr_barriers <- frs_network_features(
  conn,
  segments       = "bcfishpass.streams",
  features       = "bcfishpass.barriers_pscis",
  segment_id_col = "segmented_stream_id",
  feature_id_col = "barriers_pscis_id",
  direction      = "downstream",
  aoi            = "ADMS"
)

# Fish observations upstream of each barrier
upstr_obs <- frs_network_features(
  conn,
  segments       = "bcfishpass.barriers_pscis",
  features       = "bcfishobs.observations",
  segment_id_col = "barriers_pscis_id",
  feature_id_col = "observation_key",
  direction      = "upstream",
  aoi            = "ADMS"
)

# Generic: water-quality stations downstream of each link segment
wq_dnstr <- frs_network_features(
  conn,
  segments       = "fresh.streams",
  features       = "wq.stations_snapped",
  feature_id_col = "station_id",
  direction      = "downstream",
  aoi            = "BABL"
)

# bcfishpass.observations uses unsuffixed `wscode` / `localcode`
# columns -- pass the column names so the join matches.
obs_per_segment <- frs_network_features(
  conn,
  segments       = "bcfishpass.streams",
  features       = "bcfishpass.observations",
  segment_id_col = "segmented_stream_id",
  feature_id_col = "observation_key",
  direction      = "upstream",
  aoi                    = "ADMS",
  features_wscode_col    = "wscode",
  features_localcode_col = "localcode"
)
# feature_ids is a list-column of character vectors:
lengths(obs_per_segment$feature_ids)        # per-segment counts
obs_per_segment$feature_ids[[1]]            # character vector

# Only whether any barrier lies downstream: the segments of the first
# call, without building their arrays
has_dnstr <- frs_network_features(
  conn,
  segments       = "bcfishpass.streams",
  features       = "bcfishpass.barriers_pscis",
  segment_id_col = "segmented_stream_id",
  feature_id_col = "barriers_pscis_id",
  direction      = "downstream",
  aoi            = "ADMS",
  result         = "exists"
)
setequal(has_dnstr$segmented_stream_id, dnstr_barriers$segmented_stream_id)

DBI::dbDisconnect(conn)
} # }
```
