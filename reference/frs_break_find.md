# Find Gradient Break Locations on a Stream Network

Detect where stream gradient exceeds a threshold for a sustained
distance (island detection). Produces break points at the entry of each
steep section, suitable for
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md).

## Usage

``` r
frs_break_find(
  conn,
  table,
  to = "working.breaks",
  attribute = NULL,
  threshold = NULL,
  interval = 100L,
  distance = 100L,
  min_length = 0L,
  overwrite = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- table:

  Character. Working schema table to find breaks on (from
  [`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)).

- to:

  Character. Destination table for break points. Default
  `"working.breaks"`.

- attribute:

  Character. Column name for threshold-based breaks. Currently only
  `"gradient"` is supported.

- threshold:

  Numeric. Threshold value — sustained sections where gradient exceeds
  this produce a break point at the entry.

- interval:

  Integer. Not used (kept for compatibility). Default `100`.

- distance:

  Integer. Upstream window in metres for gradient computation at each
  vertex. Default `100`.

- min_length:

  Integer. Minimum island length in metres to keep. Default `0` (keep
  all islands — a 30m waterfall at 20% gradient is a real barrier). Set
  to `100` to restore pre-0.12.2 behavior where short steep sections
  were filtered out.

- overwrite:

  Logical. If `TRUE`, drop `to` before creating. Default `TRUE`.

## Value

`conn` invisibly, for pipe chaining.

## Details

For locating point features on the network (crossings, falls,
observations), use
[`frs_feature_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_find.md)
instead.

## See also

Other habitat:
[`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
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
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md),
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
# --- Where breaks occur (bundled data) ---
# Break points are locations where a stream attribute exceeds a threshold.
# Here: segments with gradient > 5% (potential barriers to fish passage).

d <- readRDS(system.file("extdata", "byman_ailport.rds", package = "fresh"))
streams <- d$streams

# Which segments exceed 5% gradient?
is_steep <- streams$gradient > 0.05
message(sum(is_steep, na.rm = TRUE), " of ", nrow(streams),
        " segments exceed 5% gradient")
#> 546 of 2167 segments exceed 5% gradient

# Plot: steep segments (red) are where breaks would be placed
plot(sf::st_geometry(streams), col = "grey80",
     main = "Break locations: gradient > 5%")
plot(sf::st_geometry(streams[which(is_steep), ]), col = "red", add = TRUE)
legend("topright", legend = c("below threshold", "above threshold (break)"),
       col = c("grey80", "red"), lwd = 2, cex = 0.8)


if (FALSE) { # \dontrun{
# --- Live DB usage ---
conn <- frs_db_conn()

# Attribute mode: break where gradient exceeds 5%
conn |>
  frs_extract("bcfishpass.streams_vw", "working.streams", aoi = "BULK") |>
  frs_break_find("working.streams", attribute = "gradient", threshold = 0.05)

DBI::dbDisconnect(conn)
} # }
```
