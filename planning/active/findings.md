# Findings — frs_network_features (#201)

## Issue context

A recurring pattern across stream-network analysis: for each segment in a network table, aggregate the set of point features that lie at a particular relative position (downstream of, or upstream of, that segment) and surface them as a per-segment array. Examples:

- **Barriers downstream of habitat segments** — does this stretch of stream have any access blockers between it and the river mouth? (`bcfishpass.streams_dnstr_barriers`)
- **Fish observations upstream of a barrier** — has any observed species made it past this point? (`bcfishpass.streams_upstr_observations`)
- **Water-quality stations downstream of a sample site** — what monitoring data integrates flow from this segment?
- **Sediment sample points along a project reach** — which surveys overlap our area of interest?
- **Crossings, diversions, withdrawals, weather stations** — any point feature snapped to FWA's `(blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree)` keying.

bcfishpass solves the barriers-and-observations slice via a Postgres UDF (`bcfishpass.load_dnstr_chunked`), but the SQL pattern is dataset-agnostic. fresh has the right home for the primitive — sibling to its existing `frs_network_*` family — but it doesn't exist yet, so consumers either reach into bcfp's UDF (DB-side, not in the R API) or hand-roll the SQL each time.

## Proposed signature

```r
frs_network_features(
  conn,
  segments,                              # schema-qualified segments table
  features,                              # schema-qualified features table
  segment_id_col = "id_segment",
  feature_id_col,                        # required (no default)
  direction,                             # c("downstream", "upstream"); required
  aoi = NULL,                            # WSG today, polygon/ltree later
  include_equivalents = FALSE
)
```

## SQL pattern (paraphrased)

```sql
SELECT
  a.<segment_id_col>,
  array_agg(b.<feature_id_col> ORDER BY b.wscode_ltree DESC, b.localcode_ltree DESC, b.downstream_route_measure DESC)
    FILTER (WHERE b.<feature_id_col> IS NOT NULL) AS feature_ids
FROM <segments> a
LEFT JOIN <features> b ON
  whse_basemapping.fwa_<direction>(
    a.blue_line_key, a.downstream_route_measure, a.wscode_ltree, a.localcode_ltree,
    b.blue_line_key, b.downstream_route_measure, b.wscode_ltree, b.localcode_ltree,
    <include_equivalents>, 1
  )
WHERE <aoi-resolved-WHERE-on-a>
GROUP BY a.<segment_id_col>
```

`direction` flips between `whse_basemapping.fwa_downstream` and `whse_basemapping.fwa_upstream`. Otherwise the SQL is structurally identical.

## Reference: bcfp's canonical SQL

`bcfishpass/db/migrations/archive/v0.7.6/load_dnstr_chunked.sql` is the canonical pattern. Uses INNER JOIN + array_agg with the same `ORDER BY` triple. We adapt to LEFT JOIN so segments with zero matches still appear (with NULL array). bcfp's pattern produces no row for empty-match segments; we produce one row with NULL.

## Naming + family fit

`frs_network_features` slots into the existing `frs_network_*` family:

- `frs_network_downstream(point)` — 1 origin → N segments
- `frs_network_upstream(point)` — 1 origin → N segments
- `frs_check_upstream(A, B)` — boolean: is A upstream of B?
- `frs_network_segment(point, ...)` — segment lookup at a point
- `frs_network_prune(...)` — network pruning
- **`frs_network_features(segments, features, direction, ...)` — N segments × M features → per-segment array** (this issue)

Sibling-not-replacement: segments→features is a distinct shape from point→segments.

## Out of scope (explicitly)

- The bcfp-shape `streams_access` composition (per-source × per-species wide table). That's the consumer's job (link#124 in flight).
- Generalised `aoi` polygon/ltree support — future PR when a consumer needs it.
- `direction = "any"` mode (return both upstream + downstream arrays). YAGNI.

## Existing utilities to reuse

- `.frs_validate_identifier` (`R/utils.R`) — schema-qualified table + column name validation. Already used in `frs_network_downstream`.
- `frs_db_query()` (`R/frs_db_query.R`) — canonical query helper.
- `local_mocked_bindings(frs_db_query = ...)` test pattern — copy from `tests/testthat/test-frs_network_downstream.R`.

## Live parity reference

bcfp tunnel: `localhost:63333`, db `bcfishpass`, user from `PG_USER_SHARE` env var, password from `PG_PASS_SHARE`. Compare `frs_network_features(... bcfishpass.streams, bcfishpass.barriers_pscis, direction = "downstream", aoi = "ADMS")` against `bcfishpass.streams_dnstr_barriers.barriers_pscis_dnstr` filtered to ADMS. Acceptance: byte-identical mod array-element sort.

## Earlier scratch attempt

A scratch implementation `R/frs_dnstr_features.R` was started in plan-mode exploration on a now-deleted branch (`frs-dnstr-features-primitive`). It used `LEFT JOIN LATERAL` + `array_agg` and got 15613/15647 array-equal on ADMS — 34 segments where ours had empty arrays but bcfp had non-empty. The LATERAL pattern was lossy. Phase 2's plain `LEFT JOIN` + `array_agg` should match bcfp's pattern byte-identical.
