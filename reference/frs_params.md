# Load Habitat Model Parameter Sets

Load species-specific habitat thresholds from a PostgreSQL table or a
local CSV file. Returns a list of parameter sets, one per species, ready
for iteration with [`lapply()`](https://rdrr.io/r/base/lapply.html) or
[`purrr::walk()`](https://purrr.tidyverse.org/reference/map.html) over
the `frs_break()` / `frs_classify()` pipeline.

## Usage

``` r
frs_params(
  conn = NULL,
  table = "bcfishpass.parameters_habitat_thresholds",
  csv = NULL
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object. Required when reading from a database table. Ignored when
  `csv` is provided.

- table:

  Character. Schema-qualified table name to read parameters from.
  Default `"bcfishpass.parameters_habitat_thresholds"`.

- csv:

  Character or `NULL`. Path to a local CSV file. When provided, `conn`
  and `table` are ignored.

## Value

A named list of parameter sets, keyed by species code. Each element is a
list with threshold values and a `ranges` sub-list suitable for passing
to `frs_classify()`.

## Examples

``` r
# Load species thresholds from bundled test data
params <- frs_params(csv = system.file("testdata", "test_params.csv",
  package = "fresh"))
names(params)
#> [1] "BT" "CH" "CO"

# Coho spawning: gradient 0-5.5%, channel width 2m+, MAD 0.16-9999 m3/s
params$CO$ranges$spawn
#> $gradient
#> [1] 0.0000 0.0549
#> 
#> $channel_width
#> [1]    2 9999
#> 
#> $mad_m3s
#> [1]    0.164 9999.000
#> 

# Bull trout rearing: no gradient or MAD constraint, just channel width 1.5m+
params$BT$ranges$rear
#> $channel_width
#> [1]    1.5 9999.0
#> 

if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Default: bcfishpass parameter tables (11 species)
params <- frs_params(conn)

# Drive the pipeline — one iteration per species
lapply(params, function(p) {
  message(p$species_code, ": gradient max = ", p$spawn_gradient_max)
  # frs_break(conn, ..., threshold = p$spawn_gradient_max)
  # frs_classify(conn, ..., ranges = p$ranges$spawn)
})

DBI::dbDisconnect(conn)
} # }
```
