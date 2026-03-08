# Fetch Fish Observations

Query fish observation events from a bcfishobs table. Filter by species
code, watershed group, and/or blue line key.

## Usage

``` r
frs_fish_obs(
  species_code = NULL,
  watershed_group_code = NULL,
  blue_line_key = NULL,
  table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
  cols = c("fish_observation_point_id", "species_code", "observation_date", "life_stage",
    "activity", "blue_line_key", "downstream_route_measure", "watershed_group_code",
    "wscode_ltree", "localcode_ltree", "geom"),
  limit = NULL,
  ...
)
```

## Arguments

- species_code:

  Character. Species code (e.g. `"CH"` for chinook, `"ST"` for
  steelhead). Default `NULL` (all species).

- watershed_group_code:

  Character. Watershed group code. Default `NULL`.

- blue_line_key:

  Integer. Blue line key. Default `NULL`.

- table:

  Character. Fully qualified table name. Default
  `"bcfishobs.fiss_fish_obsrvtn_events_vw"`.

- cols:

  Character vector of column names to select. Default includes the most
  commonly used observation attributes.

- limit:

  Integer. Maximum rows to return. Default `NULL`.

- ...:

  Additional arguments passed to
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md).

## Value

An `sf` data frame of fish observation events.

## See also

Other fish:
[`frs_fish_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_fish_habitat.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Chinook observations in the Bulkley
obs <- frs_fish_obs(species_code = "CH", watershed_group_code = "BULK")
} # }
```
