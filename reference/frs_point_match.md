# Match Two Point Datasets Along FWA Network Within Instream Distance

For each point in `table_a`, find the closest point in `table_b` on the
same FWA stream (`blue_line_key`) within `distance_max` instream metres,
and write the joined result to `table_to`. Each `table_a` point links to
at most one `table_b` point — the closest one within the threshold;
points with no match within the threshold appear in the output with
`<col_b_id>` set to NULL.

## Usage

``` r
frs_point_match(
  conn,
  table_a,
  table_b,
  table_to,
  distance_max,
  col_a_id = "id",
  col_b_id = "id",
  tiebreak = c("instream", "planar")
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object pointing at fwapg.

- table_a:

  Character. Schema-qualified source table. Points to match **from**.
  Must already be snapped to FWA — required columns are `blue_line_key`
  and `downstream_route_measure` plus the ID column named in `col_a_id`.

- table_b:

  Character. Schema-qualified target table. Points to match **to**. Same
  column requirements as `table_a`. The ID column named in `col_b_id` is
  the value carried over to `table_to`.

- table_to:

  Character. Schema-qualified destination. Created by this function via
  `DROP TABLE IF EXISTS` + `CREATE TABLE AS`. Columns are all of
  `table_a`'s columns plus `<col_b_id>` (the matched target ID,
  nullable) plus `distance_instream` (numeric, the absolute difference
  in `downstream_route_measure` between the matched pair; NULL for
  unmatched rows).

- distance_max:

  Numeric scalar. Maximum instream distance in metres. Computed as
  `ABS(table_a.downstream_route_measure - table_b.downstream_route_measure)`.
  bcfp's PSCIS↔modelled case uses 100.

- col_a_id:

  Character. Default `"id"`. The unique-key column on `table_a`.

- col_b_id:

  Character. Default `"id"`. The unique-key column on `table_b` carried
  forward into `table_to`.

- tiebreak:

  Character. Distance metric used to pick a winner when multiple
  `table_a` rows compete for the same `table_b` row (b-side dedup). One
  of:

  - `"instream"` (default): order by `ABS(drm_a - drm_b)`. Self-
    consistent with the threshold filter; works on any FWA-snapped point
    dataset without requiring geometry columns.

  - `"planar"`: order by `ST_Distance(a.geom, b.geom)`. Mirrors bcfp's
    `02_pscis_streams_150m.sql` tiebreak (line 190). Requires a `geom`
    column on both `table_a` and `table_b` (FWA convention). Use this
    when bcfp-byte-identical output is required and your input tables
    carry geom.

  The threshold filter (`distance_max`) and the a-side dedup tiebreak
  are instream-distance in **both** modes — only the b-side dedup
  tiebreak changes. The two modes converge when no `table_b` row has
  multiple competing `table_a` matches; they diverge only in
  clustered-point edge cases.

## Value

`conn` invisibly, for piping. Side effect: drops + recreates `table_to`.

## Details

Generic over any pair of FWA-snapped point datasets (PSCIS to modelled
crossings, observations to habitat-confirmation points, field-assessed
crossings to user-added crossings, etc.). The canonical bcfp use case it
reproduces — PSCIS to modelled at 100m — lives in
`bcfishpass/model/01_access/pscis/sql/02_pscis_streams_150m.sql` at
`smnorris/bcfishpass@v0.7.14-125-g6e9cf1c` (current `bcfishpass.log`
tunnel state at the time of writing).

Network-position columns (`blue_line_key`, `downstream_route_measure`)
are hard-coded to the FWA convention. Per-side overrides (à la
[`frs_network_features()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_features.md)
post-fresh#204) can be added if a real divergence appears.

**Single-stream-per-input assumption.** This primitive assumes each row
in `table_a` has been snapped to one FWA stream upstream of the call
(via
[`frs_point_snap()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_snap.md)
or equivalent). It does not consider alternate stream candidates within
a planar buffer. bcfp's `02_pscis_streams_150m.sql` does — it starts
from raw PSCIS points, considers all FWA streams within 150m planar,
then scores by name/width to pick the best (PSCIS, stream) pair. As a
result, `frs_point_match` matches bcfp's final
`bcfishpass.pscis.modelled_crossing_id` byte-identically when the input
PSCIS lands on the same stream bcfp chose; ~0.5% edge cases on a large
WSG (BULK validation 2026-05-11) diverge where bcfp's multi-stream
consideration picks a different stream than the caller's single-stream
snap. Workaround: caller can run multi-stream candidate selection before
calling this primitive.

**Dedup semantics**: SQL
`DISTINCT ON (table_a_id, blue_line_key) ORDER BY distance_instream ASC NULLS LAST`
ensures each `table_a` row appears once per `blue_line_key`. The closest
non-NULL match wins. Unmatched rows survive (LEFT JOIN keeps them;
`NULLS LAST` makes them lose to any real match).

**Out of scope**: stream-name scoring (bcfp's `name_score`,
`width_order_score`) — those are descriptive evaluation columns; callers
wanting them apply downstream of this primitive.

## See also

Other network:
[`frs_network_features()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_features.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# PSCIS ↔ modelled crossings at 100m instream distance (bcfp parity)
frs_point_match(
  conn,
  table_a        = "working_adms.pscis_assessment_snapped",
  table_b        = "fresh.modelled_stream_crossings",
  table_to       = "working_adms.pscis",
  distance_max   = 100,
  col_a_id = "stream_crossing_id",
  col_b_id = "modelled_crossing_id"
)

# Field-assessed crossings vs user-added crossings (deduplication)
frs_point_match(
  conn,
  table_a        = "wsg_adms.crossings_field",
  table_b        = "wsg_adms.crossings_user",
  table_to       = "wsg_adms.crossings_matched",
  distance_max   = 50,
  col_a_id = "field_id",
  col_b_id = "user_id"
)

DBI::dbDisconnect(conn)
} # }
```
