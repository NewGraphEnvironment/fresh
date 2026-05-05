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
  include_equivalents = FALSE
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

- include_equivalents:

  Logical. When `TRUE`, treats segments at the same
  `(blue_line_key, downstream_route_measure)` position as
  relative-direction matches of each other. Mirrors bcfishpass's
  `include_equivalents` arg. Default `FALSE`.

## Value

A tibble with two columns:

- `<segment_id_col>` – matches the input column name on segments

- `feature_ids` – a `text[]` array of feature IDs in the requested
  direction relative to each segment. **`NULL` when zero matches**
  (don't expect synthesised empty arrays – `array_agg` over zero rows is
  `NULL` in Postgres and that propagates).

## Details

Mirrors `bcfishpass.load_dnstr_chunked` in
`bcfishpass/db/migrations/archive/v0.7.6/load_dnstr_chunked.sql` but
generalises to either direction. The SQL pattern joins via
`whse_basemapping.fwa_<direction>()` for cross-mainstem ltree
comparison, then `array_agg`s feature IDs grouped by segment ID.

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

DBI::dbDisconnect(conn)
} # }
```
