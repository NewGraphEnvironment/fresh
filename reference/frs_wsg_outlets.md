# FWA Watershed Group Outlets

Read the bundled per-watershed-group outlet table: one row per FWA
watershed group giving the outlet `blue_line_key` +
`downstream_route_measure` and its `wscode_ltree` / `localcode_ltree`.
Regenerate with `data-raw/wsg_outlet.R`.

## Usage

``` r
frs_wsg_outlets()
```

## Value

Data frame with columns `watershed_group_code`, `blue_line_key`,
`downstream_route_measure`, `wscode_ltree`, `localcode_ltree`.

## See also

Other wsg:
[`frs_wsg_drainage()`](https://newgraphenvironment.github.io/fresh/reference/frs_wsg_drainage.md)

## Examples

``` r
head(frs_wsg_outlets())
#>   watershed_group_code blue_line_key downstream_route_measure
#> 1                 ADMS     356362743                  750.608
#> 2                 ALBN     354153558                    0.000
#> 3                 ATLL     360219387                    0.000
#> 4                 ATNA     360879335                   49.425
#> 5                 BABL     360221578                    0.000
#> 6                 BABR     360886970                   62.000
#>                      wscode_ltree                 localcode_ltree
#> 1 100.190442.999098.995997.058910 100.190442.999098.995997.058910
#> 2                      930.077174                      930.077174
#> 3               800.936764.858242        800.936764.858242.219234
#> 4               910.275583.999439               910.275583.999439
#> 5                      400.536025               400.536025.653058
#> 6                      400.536025                      400.536025
```
