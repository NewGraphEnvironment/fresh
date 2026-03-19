# FWA Edge Type Lookup Table

Return the FWA edge type codes bundled with this package, optionally
filtered by category. Source: Table 2 "Edge Type Code Table" from the
GeoBC Freshwater Atlas User Guide (GeoBC 2009, p. 11).

## Usage

``` r
frs_edge_types(category = NULL)
```

## Arguments

- category:

  Character or `NULL`. If provided, filter to rows matching this
  category. One of `"lake"`, `"wetland"`, `"river"`, `"stream"`,
  `"subsurface"`, `"connector"`, `"construction"`, `"boundary"`,
  `"unknown"`. Default `NULL` returns all rows.

## Value

A data.frame with columns `edge_type` (integer), `description`
(character), and `category` (character).

## Examples

``` r
# All edge types
frs_edge_types()
#>    edge_type
#> 1        100
#> 2        150
#> 3       1000
#> 4       1050
#> 5       1100
#> 6       1150
#> 7       1200
#> 8       1250
#> 9       1300
#> 10      1325
#> 11      1350
#> 12      1375
#> 13      1400
#> 14      1410
#> 15      1425
#> 16      1450
#> 17      1475
#> 18      1500
#> 19      1525
#> 20      1550
#> 21      1600
#> 22      1625
#> 23      1700
#> 24      1800
#> 25      1825
#> 26      1850
#> 27      1875
#> 28      1900
#> 29      1925
#> 30      1950
#> 31      1975
#> 32      2000
#> 33      2100
#> 34      2300
#> 35      5000
#> 36      5100
#> 37      5200
#> 38      5900
#> 39      6000
#> 40      6010
#> 41      6100
#>                                                                              description
#> 1                                                                              Coastline
#> 2                                                           Construction line, coastline
#> 3                                                        Single line blueline, main flow
#> 4                                        Single line blueline, main flow through wetland
#> 5                                                   Single line blueline, secondary flow
#> 6                                   Single line blueline, secondary flow through wetland
#> 7                                                           Construction line, main flow
#> 8                                        Construction line, double line river, main flow
#> 9                                                      Construction line, secondary flow
#> 10                                                  Construction line, segment delimiter
#> 11                                  Construction line, double line river, secondary flow
#> 12                                                    Construction line, river delimiter
#> 13                                     Construction line, other flow/inferred connection
#> 14                                                  Construction line, network connector
#> 15                                                    Construction line, subsurface flow
#> 16                                                         Construction line, connection
#> 17                                                           Construction line, lake arm
#> 18                                                                        Lake shoreline
#> 19                                                  Lake shoreline shared with a wetland
#> 20                                                          Construction line, lakeshore
#> 21                                                                      Island shoreline
#> 22                                                Island shoreline shared with a wetland
#> 23                                                                     Wetland shoreline
#> 24                                                      Double line blueline, right bank
#> 25                                  Double line blueline, right bank shared with wetland
#> 26                                                       Double line blueline, left bank
#> 27                                   Double line blueline, left bank shared with wetland
#> 28                                                           Island in river, right bank
#> 29                                       Island in river, right bank shared with wetland
#> 30                                                            Island in river, left bank
#> 31                                        Island in river, left bank shared with wetland
#> 32                                                                    Single line, Canal
#> 33                                                  Double line, Canal or Reservoir bank
#> 34                                                    Single-line, Canal, secondary flow
#> 35                                                              Major watershed boundary
#> 36                                                              Minor watershed boundary
#> 37                                                Watershed boundary (manually modified)
#> 38                                                           Isolated watershed boundary
#> 39                                                     International/Provincial Boundary
#> 40 Construction Line, connectors (for streams that leave and re-enter a watershed group)
#> 41  Non-BC International/Provincial Boundary (appears only in extra-jurisdictional data)
#>        category
#> 1     coastline
#> 2  construction
#> 3        stream
#> 4        stream
#> 5        stream
#> 6        stream
#> 7  construction
#> 8  construction
#> 9  construction
#> 10 construction
#> 11 construction
#> 12 construction
#> 13    connector
#> 14    connector
#> 15   subsurface
#> 16    connector
#> 17 construction
#> 18         lake
#> 19         lake
#> 20 construction
#> 21       island
#> 22       island
#> 23      wetland
#> 24        river
#> 25        river
#> 26        river
#> 27        river
#> 28       island
#> 29       island
#> 30       island
#> 31       island
#> 32        canal
#> 33        canal
#> 34        canal
#> 35     boundary
#> 36     boundary
#> 37     boundary
#> 38     boundary
#> 39     boundary
#> 40    connector
#> 41     boundary

# Just lake codes
frs_edge_types(category = "lake")
#>    edge_type                          description category
#> 18      1500                       Lake shoreline     lake
#> 19      1525 Lake shoreline shared with a wetland     lake

# Stream-type codes (definite, probable, intermittent, inferred)
frs_edge_types(category = "stream")
#>   edge_type                                          description category
#> 3      1000                      Single line blueline, main flow   stream
#> 4      1050      Single line blueline, main flow through wetland   stream
#> 5      1100                 Single line blueline, secondary flow   stream
#> 6      1150 Single line blueline, secondary flow through wetland   stream

# Use with frs_classify() to scope classification by waterbody type
lake_codes <- frs_edge_types(category = "lake")$edge_type
paste("edge_type IN (", paste(lake_codes, collapse = ", "), ")")
#> [1] "edge_type IN ( 1500, 1525 )"
```
