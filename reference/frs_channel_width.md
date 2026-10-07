# Estimate Channel Width from a Bankfull Regression

Write a channel width predicted from upstream drainage area and mean
annual precipitation onto a working table, via SQL `UPDATE`. By default
it fills only rows where the target column is `NULL`. That gives every
segment with both inputs a width, including the first-order streams that
`fwa_stream_networks_channel_width` leaves `NULL`, while leaving
measured and mapped widths alone. FWA placeholder (`999`) and unmapped
segments have no upstream area, so they stay `NULL` unless `value` is
given. Point `to` at a new column instead to get an independent estimate
to compare against existing widths.

## Usage

``` r
frs_channel_width(
  conn,
  table,
  model = "poisson2021",
  to = "channel_width",
  col_area = "upstream_area_ha",
  col_precip = "map_upstream",
  col_source = paste0(to, "_source"),
  overwrite = FALSE,
  value = NULL,
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- table:

  Character. Schema-qualified working table to update.

- model:

  Regression to apply. `"poisson2021"` (default), `"hall2007"`, or a
  named list of coefficients for a custom power law (see Details).

- to:

  Character. Column to write. Added as `double precision` if missing.
  Default `"channel_width"`.

- col_area:

  Character. Upstream drainage area column, in hectares. Default
  `"upstream_area_ha"`.

- col_precip:

  Character. Mean annual precipitation column, in millimetres. Default
  `"map_upstream"`.

- col_source:

  Character or `NULL`. Column labelling which rows this call wrote,
  added as `text` if missing. Default `"<to>_source"`, so a comparison
  column (`to = "channel_width_hall"`) never relabels
  `channel_width_source`. `NULL` writes no label.

- overwrite:

  Logical. `FALSE` (default) writes only rows where `to` is `NULL`.
  `TRUE` rewrites every row: the regression where its inputs allow,
  `NULL` elsewhere.

- value:

  Numeric or `NULL`. A width (m) for rows still `NULL` after the
  regression, labelled `ASSIGNED`: typically segments with no upstream
  area, such as FWA placeholder and unmapped lines. Default `NULL`
  leaves them `NULL`.

- verbose:

  Logical. Report how many rows were modelled, assigned and left `NULL`.
  Default `TRUE`.

## Value

`conn` invisibly, for pipe chaining.

## Details

The function reads columns that must already be on `table`. It does no
network-specific joins. For FWA networks, add them with
[`frs_col_join()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_join.md)
(see Examples).

Every model is one power law:

    width = k * ((area_ha + a_off) / a_div)^a * ((precip_mm + p_off) / p_div)^b

- `"poisson2021"`:

  Thorley and Irvine (2021b), Poisson Consulting. The model behind the
  `MODELLED` widths in `fwa_stream_networks_channel_width` (fwapg
  `extras/channel_width/sql/channel_width_modelled.sql`):
  `k = exp(0.30713)`, `a = b = 0.4577882`, `a_div = 100`,
  `p_div = 1000`, `a_off = p_off = 1`, rounded to 2 decimals. Label
  `MODELLED_POISSON2021`.

- `"hall2007"`:

  The bankfull width regression of the Valley Confinement Algorithm
  (Hall et al. 2007), as used by flooded:
  `(area_km2 ^ 0.280) * 0.196 * (precip_cm ^ 0.355)`. Here `k = 0.196`,
  `a = 0.280`, `b = 0.355`, `a_div = 100` (ha to km2), `p_div = 10` (mm
  to cm), no offsets, no rounding. It runs below poisson2021 except on
  small catchments, where the crossover depends on precipitation: about
  65 ha at 100 mm, 16 ha at 1000 mm and 5 ha at 4000 mm. Label
  `MODELLED_HALL2007`.

- custom:

  A named list with numeric `k`, `a`, `b`, `a_div`, `p_div`, `a_off`,
  `p_off`, and optionally `digits` (rounding). Label `MODELLED_CUSTOM`.

A row is written only where both `area + a_off` and `precip + p_off` are
positive, so rows with a `NULL` input stay `NULL`. With poisson2021's
offset of 1, an input of 0 is still written. Unlike fwapg, a `NULL`
precipitation is not treated as 0.

**Matching fwapg.** fwapg computes `MODELLED` once per `wscode_ltree` /
`localcode_ltree` pair, from the largest upstream area among that pair's
watershed polygons. So every segment on a reach gets the width at its
downstream end. To reproduce it, join that group maximum as the area
column (second example). On the Bulkley group, that join puts 94% of
`MODELLED` rows within 5%, against about 10% for each segment's own
area.

## See also

Other habitat:
[`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
[`frs_categorize()`](https://newgraphenvironment.github.io/fresh/reference/frs_categorize.md),
[`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md),
[`frs_cluster()`](https://newgraphenvironment.github.io/fresh/reference/frs_cluster.md),
[`frs_col_generate()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_generate.md),
[`frs_col_join()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_join.md),
[`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md),
[`frs_feature_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_find.md),
[`frs_feature_index()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_index.md),
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md),
[`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md),
[`frs_habitat_overlay()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_predicates()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_predicates.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md),
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Inputs: upstream area (ha) and mean annual precipitation (mm)
conn |>
  frs_col_join("working.streams",
    from = "(SELECT l.linear_feature_id, ua.upstream_area_ha
             FROM fwa_streams_watersheds_lut l
             JOIN fwa_watersheds_upstream_area ua
               ON l.watershed_feature_id = ua.watershed_feature_id)",
    cols = "upstream_area_ha",
    by = "linear_feature_id") |>
  frs_col_join("working.streams",
    from = "fwa_stream_networks_mean_annual_precip",
    cols = "map_upstream",
    by = c("wscode_ltree", "localcode_ltree"))

# Fill NULL widths (first-order streams), 0.5 m where inputs are missing
conn |>
  frs_channel_width("working.streams", value = 0.5)

# Independent estimates alongside the existing widths
conn |>
  frs_channel_width("working.streams", to = "channel_width_poisson") |>
  frs_channel_width("working.streams", model = "hall2007",
    to = "channel_width_hall")

# fwapg-matching area: the largest upstream area per watershed-code pair
conn |>
  frs_col_join("working.streams",
    from = "(SELECT s.wscode_ltree, s.localcode_ltree,
                    max(ua.upstream_area_ha) AS upstream_area_ha
             FROM fwa_stream_networks_sp s
             JOIN fwa_streams_watersheds_lut l
               ON s.linear_feature_id = l.linear_feature_id
             JOIN fwa_watersheds_upstream_area ua
               ON l.watershed_feature_id = ua.watershed_feature_id
             -- the watershed group(s) your table covers
             WHERE s.watershed_group_code = 'BULK'
             GROUP BY s.wscode_ltree, s.localcode_ltree)",
    cols = "upstream_area_ha",
    by = c("wscode_ltree", "localcode_ltree"))

DBI::dbDisconnect(conn)
} # }
```
