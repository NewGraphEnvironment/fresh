# Validate Cluster Connectivity on Stream Network

Check whether clusters of segments sharing one label are connected to
segments with another label on the stream network. Disconnected clusters
have their label set to `FALSE`.

## Usage

``` r
frs_cluster(
  conn,
  table,
  habitat,
  label_cluster = "rearing",
  label_connect = "spawning",
  species = NULL,
  direction = "upstream",
  bridge_gradient = 0.05,
  bridge_distance = 10000,
  confluence_m = 10,
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

  Character. Schema-qualified streams table with geometry and ltree
  columns (from
  [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)).

- habitat:

  Character. Schema-qualified habitat table with boolean label columns
  (from
  [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)).

- label_cluster:

  Character. Boolean column name in `habitat` to cluster on. Default
  `"rearing"`.

- label_connect:

  Character. Boolean column name in `habitat` that must exist in the
  specified direction for a cluster to be valid. Default `"spawning"`.

- species:

  Character vector or `NULL`. Species codes to process. `NULL` processes
  all species in the habitat table. Default `NULL`.

- direction:

  Character. Where the connection must be relative to the cluster:
  `"upstream"`, `"downstream"`, or `"both"`. Default `"upstream"`.

- bridge_gradient:

  Numeric. Maximum gradient on any single segment between cluster and
  connection. Applied segment-by-segment along the downstream trace
  path. Upstream check is boolean (no gradient constraint) because the
  branching network makes path ordering unreliable. Default `0.05` (5%).

- bridge_distance:

  Numeric. Maximum cumulative network distance in metres to search for
  connection downstream. Default `10000` (10 km).

- confluence_m:

  Numeric. Confluence tolerance in metres. When a cluster's
  most-downstream point is within this distance of a confluence, the
  upstream check also considers the parent stream. Default `10`.

- verbose:

  Logical. Print progress. Default `TRUE`.

## Value

`conn` invisibly, for pipe chaining.

## Details

Uses `ST_ClusterDBSCAN(geom, 1, 1)` to group physically adjacent
segments, then validates each cluster by checking for `label_connect` in
the specified direction.

## See also

Other habitat:
[`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
[`frs_categorize()`](https://newgraphenvironment.github.io/fresh/reference/frs_categorize.md),
[`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md),
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
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# --- Why cluster connectivity matters ---
#
# frs_habitat_classify() labels segments as rearing or spawning
# based on gradient and channel width. But a rearing segment has
# no ecological value for anadromous species unless juveniles can
# reach spawning habitat. A headwater stream with perfect rearing
# conditions but no spawning upstream or downstream is a dead end.
#
# frs_cluster() groups adjacent rearing segments into clusters,
# then checks if each cluster connects to spawning on the network.
# Disconnected clusters get rearing set to FALSE.

# After frs_network_segment() + frs_habitat_classify():
DBI::dbGetQuery(conn, "
  SELECT count(*) FILTER (WHERE rearing) AS rearing_before
  FROM fresh.streams_habitat
  WHERE species_code = 'CO'")
#>   rearing_before
#> 1             33

# Upstream check: keep rearing only if spawning exists upstream.
# Anadromous juveniles rear downstream of where adults spawn.
frs_cluster(conn,
  table = "fresh.streams",
  habitat = "fresh.streams_habitat",
  species = "CO",
  direction = "upstream")
#>   CO: 2 disconnected removed (31 rearing remaining, 0.6s)

# Downstream check: keep rearing only if spawning exists downstream
# within 10km, with no segment steeper than 5% in between.
# Juveniles can drift downstream but can't pass steep barriers
# to reach spawning habitat above.
frs_cluster(conn,
  table = "fresh.streams",
  habitat = "fresh.streams_habitat",
  species = "CO",
  direction = "downstream",
  bridge_gradient = 0.05,
  bridge_distance = 10000)

# Both directions — valid if connected in either direction.
# Run per species with parameters from parameters_fresh.csv:
pf <- utils::read.csv(system.file("extdata",
  "parameters_fresh.csv", package = "fresh"))
for (i in which(pf$cluster_rearing)) {
  sp <- pf$species_code[i]
  frs_cluster(conn,
    table = "fresh.streams",
    habitat = "fresh.streams_habitat",
    species = sp,
    direction = pf$cluster_direction[i],
    bridge_gradient = pf$cluster_bridge_gradient[i],
    bridge_distance = pf$cluster_bridge_distance[i],
    confluence_m = pf$cluster_confluence_m[i])
}

DBI::dbDisconnect(conn)
} # }
```
