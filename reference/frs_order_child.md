# Classify rearing on direct children of large-order streams

Post-classification update that adds a habitat label (default `rearing`)
to segments on direct tributaries of large-order rivers, optionally
distance-capped from the confluence. Runs after
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
(and any post-classify step like
[`frs_cluster()`](https://newgraphenvironment.github.io/fresh/reference/frs_cluster.md));
is additive, idempotent, and never overrides segments above an
inaccessible barrier.

## Usage

``` r
frs_order_child(
  conn,
  table,
  habitat,
  species,
  label = "rearing",
  parent_order_min = 5L,
  child_order_min = NULL,
  child_order_max = NULL,
  distance_max = NULL,
  verbose = TRUE
)
```

## Arguments

- conn:

  DBI connection.

- table:

  Character. Schema-qualified streams table (e.g. `"fresh.streams"`).

- habitat:

  Character. Schema-qualified habitat table (e.g.
  `"fresh.streams_habitat"`).

- species:

  Character. Species code (e.g. `"BT"`).

- label:

  Character. Habitat-table column to set TRUE. Default `"rearing"`.
  Generic on the column name — pass `"lake_rearing"`,
  `"wetland_rearing"`, or any custom boolean column when biology
  supports it.

- parent_order_min:

  Integer. Minimum parent stream order for a direct-child segment to
  qualify. Default `5L` (matches bcfishpass's hard-coded value).

- child_order_min:

  Integer or `NULL`. If set, segment's `stream_order` must be
  `>= child_order_min`. Default `NULL`. When both `child_order_min` and
  `child_order_max` are `NULL`, both default to `1L` (matches
  bcfishpass's `stream_order = 1` predicate).

- child_order_max:

  Integer or `NULL`. If set, segment's `stream_order` must be
  `<= child_order_max`. Default `NULL`. When both `child_order_min` and
  `child_order_max` are `NULL`, both default to `1L` (matches
  bcfishpass's `stream_order = 1` predicate).

- distance_max:

  Numeric or `NULL`. If set, segment's `downstream_route_measure` must
  be `<= distance_max` (metres from tributary mouth). Default `NULL`
  (whole tributary).

- verbose:

  Logical. Print before/after counts. Default `TRUE`.

## Value

Invisibly, the number of segments newly labeled.

## Why this exists

Small streams flowing directly into mainstem rivers support juvenile
rearing even when the FWA-measured channel width is below the species
threshold. The parent river supplies flow, temperature, access; cool
tributary water mixes at the confluence; backwater / off-channel habitat
near the mouth is high-value. Channel-width measurement on the small
tributary doesn't reflect this reality.

bcfishpass models this with a hard-coded predicate
`cw.channel_width >= rear_channel_width_min OR (s.stream_order_parent >= 5 AND s.stream_order = 1)`
(per BT/CH/CO/ ST/WCT rear SQL in
`model/02_habitat_linear/sql/load_habitat_linear_<sp>.sql`). This
function exposes the same biology as a parametric post-classification
rule, so callers can tune `parent_order_min`, `child_order_min/max`, and
`distance_max` without touching the rule grammar.

## Direct-child semantics

A "direct child" of a large river is a segment whose stream_order
matches the caller's child-order filter (`child_order_min` /
`child_order_max`) AND whose `stream_order_parent` (the order of the
river it flows into) is `>= parent_order_min`:

    s.stream_order_parent >= parent_order_min
    [AND s.stream_order >= child_order_min]
    [AND s.stream_order <= child_order_max]

Default child filter is `stream_order = 1` (matches bcfishpass's
hard-coded predicate exactly). Pass `child_order_min` /
`child_order_max` to widen — e.g.
`child_order_min = 1, child_order_max = 2` for order-1 and order-2
tributaries.

## Distance grain

`distance_max` filters on the segment's start measure
(`downstream_route_measure`). The grain of FWA segmentation determines
what gets captured at the boundary — segments straddling the cap are
kept (whole-segment-in, biology-conservative overshoot). Documented as a
tradeoff in fresh#158; alternate exact break + filter approaches are out
of scope here.

## SQL emitted

    UPDATE <habitat>
    SET <label> = TRUE
    FROM <table> s
    WHERE <habitat>.id_segment = s.id_segment
      AND <habitat>.species_code = '<species>'
      AND <habitat>.accessible = TRUE
      AND <habitat>.<label> IS NOT TRUE
      AND s.stream_order_parent >= <parent_order_min>
      AND s.stream_order >= <child_order_min>   -- default 1 if both NULL
      AND s.stream_order <= <child_order_max>   -- default 1 if both NULL
      [AND s.downstream_route_measure <= <distance_max>]

Bracketed clauses are emitted only when the corresponding parameter is
non-NULL.

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Reproduce bcfishpass exactly: direct children of order-5+ rivers,
# no distance cap, for BT/CH/CO/ST/WCT.
for (sp in c("BT", "CH", "CO", "ST", "WCT")) {
  frs_order_child(conn, "fresh.streams", "fresh.streams_habitat",
    species = sp)
}

# Distance-capped: only the lower 300 m of each direct-child trib.
frs_order_child(conn, "fresh.streams", "fresh.streams_habitat",
  species = "BT", distance_max = 300)

# Restrict to 3rd-order-and-above direct children of major rivers.
frs_order_child(conn, "fresh.streams", "fresh.streams_habitat",
  species = "BT", child_order_min = 3)
} # }
```
