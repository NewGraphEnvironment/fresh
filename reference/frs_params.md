# Load Habitat Model Parameter Sets

Load species-specific habitat thresholds from a PostgreSQL table or a
local CSV file. Returns a list of parameter sets, one per species, ready
for iteration with [`lapply()`](https://rdrr.io/r/base/lapply.html) or
[`purrr::walk()`](https://purrr.tidyverse.org/reference/map.html) over
the
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md)
/
[`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md)
pipeline.

## Usage

``` r
frs_params(
  conn = NULL,
  table = "bcfishpass.parameters_habitat_thresholds",
  csv = NULL,
  rules_yaml = system.file("extdata", "parameters_habitat_rules.yaml", package = "fresh")
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).
  Required when reading from a database table. Use `NULL` when reading
  from a CSV file.

- table:

  Character. Schema-qualified table name to read parameters from.
  Default `"bcfishpass.parameters_habitat_thresholds"`.

- csv:

  Character or `NULL`. Path to a local CSV file. When provided, `conn`
  and `table` are ignored.

- rules_yaml:

  Character or `NULL`. Path to a habitat rules YAML file. Default reads
  the bundled `inst/extdata/parameters_habitat_rules.yaml`. Pass `NULL`
  to skip rules entirely (every species falls through to the CSV ranges
  path used pre-0.12.0). When a rules file is loaded, each species
  listed in the file gets `$rules$spawn` and `$rules$rear` attached to
  its params entry. Species not listed in the file fall through to the
  CSV ranges path. See the `parameters_habitat_rules.yaml` header for
  the rule format.

## Value

A named list of parameter sets, keyed by species code. Each element is a
list with threshold values and a `ranges` sub-list suitable for passing
to
[`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md).

## See also

Other parameters:
[`frs_wsg_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_wsg_species.md)

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
