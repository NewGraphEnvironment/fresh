# Distance from Each Segment Down to the Nearest River

For every segment of a segmented streams table whose own discharge is
below a threshold, walks the network downstream and records the distance
to the nearest segment carrying at least that discharge. A habitat
rule's `near_river` condition reads the result, so a small stream close
to a large river can pass a rule whose size test it fails (see
[`frs_habitat_predicates()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_predicates.md)).
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
calls this itself when a rule asks; call it directly to inspect the
distances.

## Usage

``` r
frs_near_river(conn, table, to, discharge_min, distance_max, verbose = TRUE)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- table:

  Character. Schema-qualified segmented streams table with `id_segment`,
  `watershed_group_code`, `blue_line_key`, `watershed_key`,
  `downstream_route_measure`, `wscode_ltree`, `localcode_ltree`,
  `edge_type`, `waterbody_key`, `length_metre`, `mad_m3s` and `geom`.

- to:

  Character. Schema-qualified output table, created if it does not
  exist, with columns `id_segment`, `watershed_group_code`,
  `discharge_min`, `distance_max` and `dist_m`. A `near_river` rule
  reads only rows of its own exact pair, so build the table with the
  pairs the rules carry
  ([`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  does): a walk at a longer distance does not serve a rule with a
  shorter one. Rows for the watershed groups in `table` are replaced on
  every call; other groups' rows are kept.

- discharge_min:

  Numeric vector. River discharges to find (m3/s), each finite and above
  zero.

- distance_max:

  Numeric vector, one per `discharge_min`. Farthest distance (m) to
  record for that pair. Each pair is walked on its own, so a pair's
  distances never depend on the other pairs in the call; pairs must be
  distinct.

- verbose:

  Logical. Print rows written, segments with no local code, and timing.
  Default `TRUE`.

## Value

`conn` invisibly, for pipe chaining.

## Details

The walk follows main flow (`blue_line_key = watershed_key`), as the
other downstream traces in fresh do, so a side channel starts on the
main stem below it.

**Where the distance starts and ends.**

- It starts at the segment's **downstream end**, so a long segment whose
  lower end is within the distance passes whole.

- It ends at the bank of the river, not at its centreline. Where a
  tributary meets a river drawn as a polygon, its line crosses the
  polygon as a connector (FWA edge types 1400 and 1450) to the
  centreline. A connector carries the tributary's own small flow, so it
  is never a target, and the connector inside the target's polygon (same
  `waterbody_key`) is left out of the distance. FWA draws about a third
  of connectors as side lines, which the walk does not follow; the walk
  then jumps from the tributary's mouth to the centreline, and that jump
  is left out too. A connector inside a polygon the walk only passes
  through, because that river is too small, stays in the distance.

- Any other jump between consecutive rows of the path is counted at its
  straight length: a side channel the walk does not follow, or a stretch
  of river outside `table` that the path leaves and re-enters.

- Where a tributary joins its parent follows FWA's local codes, as in
  every downstream trace in fresh. Where a code places the confluence
  away from where the lines meet, the distance can differ from a walk
  that enters at the nearest point, either way: longer by a counted
  jump, or shorter by the stretch between the two points.

**Which segments are measured.** Only segments whose own `mad_m3s` is
NULL or below `discharge_min` get a row: a river large enough to be a
target passes or fails on its own size test, never on its distance to
itself. A segment with NULL `mad_m3s` is never a target.

**Limits.**

- The walk sees only `table`. A working table holds one watershed group,
  so a river beyond the group's outlet is not found.

- To stay fast, the walk joins only rows within `distance_max` (plus the
  longest connector run) in a straight line, and cuts the path where a
  row it skipped was directly above the next row on that row's line. A
  path that jumps out of that reach and comes back in a way that test
  cannot see (the skipped run ends a line, or the row above is out of
  step with its local code) can read short. It needs a jump between path
  rows; none occurs on BULK at 3 m3/s within 1 or 20 km.

- A segment with no local watershed code (`localcode_ltree` NULL), which
  is most side channels (edge types 1100, 1150, 1350), has no place in
  `FWA_Downstream()`'s ordering. It never walks, so it gets no row and
  never passes on `near_river`. Their count is reported when `verbose`.

## See also

Other habitat:
[`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
[`frs_categorize()`](https://newgraphenvironment.github.io/fresh/reference/frs_categorize.md),
[`frs_channel_width()`](https://newgraphenvironment.github.io/fresh/reference/frs_channel_width.md),
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
[`frs_habitat_overlay()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_predicates()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_predicates.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md),
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Segments within 1 km of a river carrying 3 m3/s, BULK working table
frs_near_river(conn, "working_bulk.streams", "working_bulk.near_river",
  discharge_min = 3, distance_max = 1000)

DBI::dbGetQuery(conn, "
  SELECT count(*) AS n, round(avg(dist_m)) AS mean_m
  FROM working_bulk.near_river WHERE discharge_min = 3")

DBI::dbDisconnect(conn)
} # }
```
