# Classify Features by Attribute Ranges, Breaks, or Overrides

Label features in a working table by any combination of: attribute
ranges (e.g. gradient between 0 and 0.025), spatial relationship to
break points (accessible vs not), and manual overrides from a
corrections table. At least one of `ranges`, `breaks`, or `overrides` is
required.

## Usage

``` r
frs_classify(
  conn,
  table,
  label,
  ranges = NULL,
  breaks = NULL,
  overrides = NULL,
  value = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- table:

  Character. Working schema table to classify (from
  [`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)).

- label:

  Character. Column name to add or update with the classification result
  (e.g. `"spawning"`, `"accessible"`).

- ranges:

  Named list or `NULL`. Each element is a column name mapped to a
  `c(min, max)` range. All conditions must be met (AND). Example:
  `list(gradient = c(0, 0.025), channel_width = c(2, 20))`.

- breaks:

  Character or `NULL`. Table name containing break points. Segments with
  no downstream break are labelled `TRUE` (accessible). Uses
  `fwa_downstream()` for network position check.

- overrides:

  Character or `NULL`. Table name containing manual corrections. Must
  have a column matching `label` and a join column matching the working
  table (default: `blue_line_key` + `downstream_route_measure`).

- value:

  Logical. Value to set when conditions are met. Default `TRUE`. Use
  `FALSE` for exclusion labels.

## Value

`conn` invisibly, for pipe chaining.

## Details

Pipeable for multi-step labelling — call once per label column:

    conn |>
      frs_classify("working.streams", label = "accessible",
                   breaks = "working.breaks") |>
      frs_classify("working.streams", label = "spawning",
                   ranges = list(gradient = c(0, 0.025)))

## See also

Other habitat:
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
[`frs_col_generate()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_generate.md),
[`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)

## Examples

``` r
# --- Concept: classify by gradient range (bundled data) ---
d <- readRDS(system.file("extdata", "byman_ailport.rds", package = "fresh"))
streams <- d$streams

# Which segments have spawning-suitable gradient (0-2.5%)?
suitable <- !is.na(streams$gradient) &
  streams$gradient >= 0 & streams$gradient <= 0.025
streams$spawning <- suitable
message(sum(suitable), " of ", nrow(streams), " segments suitable")
#> 1137 of 2167 segments suitable

plot(streams["spawning"],
     main = "Spawning habitat (gradient 0-2.5%)",
     pal = c("grey80", "steelblue"), key.pos = 1)


if (FALSE) { # \dontrun{
# --- Live DB: classify pipeline ---
conn <- frs_db_conn()
aoi <- d$aoi

conn |>
  frs_extract("whse_basemapping.fwa_stream_networks_sp",
    "working.demo_classify", aoi = aoi, overwrite = TRUE) |>
  frs_col_generate("working.demo_classify") |>
  frs_classify("working.demo_classify", label = "spawning",
    ranges = list(gradient = c(0, 0.025)))

result <- frs_db_query(conn,
  "SELECT spawning, gradient, geom FROM working.demo_classify")
plot(result["spawning"], main = "Classified: spawning habitat")

# Clean up
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_classify")
DBI::dbDisconnect(conn)
} # }
```
