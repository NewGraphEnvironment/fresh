# Fetch Modelled Fish Habitat from bcfishpass

Query stream segments with habitat model outputs from a bcfishpass
table. Filter by watershed group and/or blue line key. Returns segments
with barrier, access, and habitat classification columns.

## Usage

``` r
frs_fish_habitat(
  watershed_group_code = NULL,
  blue_line_key = NULL,
  table = "bcfishpass.streams_vw",
  cols = c("segmented_stream_id", "blue_line_key", "waterbody_key",
    "downstream_route_measure", "upstream_area_ha", "gnis_name", "stream_order",
    "channel_width", "gradient", "mad_m3s", "watershed_group_code", "wscode",
    "localcode", "geom"),
  limit = NULL,
  ...
)
```

## Arguments

- watershed_group_code:

  Character. Watershed group code. Default `NULL`.

- blue_line_key:

  Integer. Blue line key. Default `NULL`.

- table:

  Character. Fully qualified table name. Default
  `"bcfishpass.streams_vw"`.

- cols:

  Character vector of column names to select. Default includes the most
  commonly used habitat model attributes.

- limit:

  Integer. Maximum rows to return. Default `NULL`.

- ...:

  Additional arguments passed to
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md).

## Value

An `sf` data frame of stream segments with bcfishpass habitat model
columns (barriers, access, gradient, channel width, etc.).

## See also

Other fish:
[`frs_fish_obs()`](https://newgraphenvironment.github.io/fresh/reference/frs_fish_obs.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Habitat model for the Bulkley
habitat <- frs_fish_habitat(watershed_group_code = "BULK", limit = 100)
} # }
```
