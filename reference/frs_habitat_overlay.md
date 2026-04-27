# Overlay flags from one table onto another

OR-in boolean flags from a source table (`from`) onto an existing
classified table (`to`), purely additively (`FALSE → TRUE` only, never
reversed). Surfaced for the bcfishpass / link blend of rule-based
classification
([`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md))
with manually-curated knowns (`user_habitat_classification.csv`), but
the mechanism is generic: any boolean-flagged source over any
boolean-flagged target.

## Usage

``` r
frs_habitat_overlay(
  conn,
  from,
  to,
  bridge = NULL,
  species = NULL,
  habitat_types = c("spawning", "rearing", "lake_rearing", "wetland_rearing"),
  by = c("blue_line_key", "downstream_route_measure"),
  species_col = "species_code",
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- from:

  Character. Schema-qualified source table providing the flags to
  overlay. Must follow the canonical shape — see "Source-table shape"
  above.

- to:

  Character. Schema-qualified destination table to UPDATE in place. Must
  have boolean columns named in `habitat_types` plus a `species_code`
  column. Either has the join keys (`by`) directly, or only `id_segment`
  (use `bridge` to resolve).

- bridge:

  Character or `NULL`. Optional schema-qualified segments table
  providing `id_segment` + the join keys in `by`

  - `downstream_route_measure` + `upstream_route_measure`. When
    provided, switches to a 3-way range-containment join. Default `NULL`
    (direct point-match join — `to` must have the join keys). **Note:**
    the range column names are currently hardcoded to FWA convention
    (`downstream_route_measure` / `upstream_route_measure`). `from` and
    `bridge` must both use these names; non-FWA segment schemas would
    need a follow-up parameterisation.

- species:

  Character vector. Species codes to ingest. `NULL` (default) processes
  every species code present in `to`.

- habitat_types:

  Character vector. Habitat-type columns to OR in. Defaults to the four
  standard ones:
  `c("spawning", "rearing", "lake_rearing", "wetland_rearing")`. Each
  must be present in both `to` (as a boolean column) and `from` (as a
  per-row indicator column).

- by:

  Character vector. Columns used to match `from` to either `to` (when
  `bridge = NULL`) or to `bridge` (when bridge supplied). Default
  `c("blue_line_key", "downstream_route_measure")`.

- species_col:

  Character. Name of the column in `from` carrying the species code per
  row. Default `"species_code"`.

- verbose:

  Logical. Print per-species per-habitat summary. Default `TRUE`.

## Value

`conn` invisibly (for piping).

## Details

### Source-table shape

One row per (segment × species). Each row has:

- the join keys named in `by` (default
  `c("blue_line_key", "downstream_route_measure")`)

- a column carrying the species code (named in `species_col`, default
  `"species_code"`)

- one column per habitat type (named in `habitat_types`, default
  `c("spawning", "rearing", "lake_rearing", "wetland_rearing")`)

Indicator columns can be integer (`1` truthy, `0`/`NULL` falsy), text
(`'true'`/`'t'`/`'1'` truthy, anything else falsy, case + whitespace
insensitive), or boolean.

Sources in other shapes — bcfishpass's pre-2026-04-26 long format
(`habitat_type` rows + `habitat_ind` indicator), or the
per-species-suffixed wide layout (`spawning_sk`, `rearing_sk`) —
transform first via a SQL view or `data-raw/` script, then call overlay.
Shape-translation lives with the consumer.

### Two join modes (`bridge`)

- **Direct (`bridge = NULL`)** — the `to` table has the join keys
  directly. SQL does `to.<by> = from.<by>` (point match).

- **Bridged (`bridge = "<segments_table>"`)** — the `to` table is keyed
  by `id_segment` (e.g. `fresh.streams_habitat`) and lacks the
  geographic keys in `by`. The bridge table provides the link, with
  `id_segment` + range columns. SQL does a 3-way join:

      to.id_segment = bridge.id_segment
      AND bridge.<by[1]> = from.<by[1]>
      AND bridge.downstream_route_measure >= from.downstream_route_measure
      AND bridge.upstream_route_measure   <= from.upstream_route_measure

  Range containment, not point match — covers the case where one `from`
  row's `[drm, urm]` range maps to multiple bridge segments (e.g. when
  other break sources fall inside the range).

Future bridges aren't required to be `fresh.streams` — any table
providing `id_segment` + the join-key columns + range columns works. Use
cases include lake / wetland centerline segments or cottonwood-polygon
segmentations pinned to a hydrology network.

## See also

Other habitat:
[`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
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
[`frs_habitat_predicates()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_predicates.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md),
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Direct join (target has the keys):
frs_habitat_overlay(conn,
  from = "ws.user_habitat_classification",
  to   = "ws.streams_habitat_keyed")

# Bridged join (target is fresh.streams_habitat, keyed by id_segment):
frs_habitat_overlay(conn,
  from   = "ws.user_habitat_classification",
  to     = "fresh.streams_habitat",
  bridge = "fresh.streams")

# Source uses a non-canonical shape (e.g. legacy long format):
# transform first via a SQL view, then overlay against the view.
DBI::dbExecute(conn, "
  CREATE OR REPLACE VIEW ws.uhc_canonical AS
  SELECT blue_line_key, downstream_route_measure,
         upstream_route_measure, species_code,
         MAX(CASE WHEN habitat_type = 'spawning'
                  THEN habitat_ind::text END) AS spawning,
         MAX(CASE WHEN habitat_type = 'rearing'
                  THEN habitat_ind::text END) AS rearing
  FROM ws.user_habitat_classification_long
  GROUP BY 1,2,3,4")
frs_habitat_overlay(conn,
  from   = "ws.uhc_canonical",
  to     = "fresh.streams_habitat",
  bridge = "fresh.streams")
} # }
```
