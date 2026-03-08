# Filter Stream Segments by Strahler Order

Simple filter on an sf data frame of stream segments. Keeps rows where
`stream_order >= min_order`.

## Usage

``` r
frs_order_filter(streams, min_order)
```

## Arguments

- streams:

  An `sf` data frame with a `stream_order` column (e.g. from
  [`frs_stream_fetch()`](https://newgraphenvironment.github.io/fresh/reference/frs_stream_fetch.md)
  or
  [`frs_network_upstream()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_upstream.md)).

- min_order:

  Integer. Minimum Strahler stream order to keep.

## Value

An `sf` data frame with low-order streams removed.

## See also

Other prune:
[`frs_network_prune()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_prune.md)

## Examples

``` r
if (FALSE) { # \dontrun{
streams <- frs_stream_fetch(watershed_group_code = "BULK")
big_streams <- frs_order_filter(streams, min_order = 4)
} # }
```
