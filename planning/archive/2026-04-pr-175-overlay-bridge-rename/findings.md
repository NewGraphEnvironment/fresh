# Findings — #174 overlay rename + bridge

## Naming convention surveyed (2026-04-26)

| pattern | examples |
|---|---|
| `to` for write destination | `frs_habitat_classify(to)`, `frs_break_apply(to)`, `frs_aggregate(to)` |
| `from` for read source | `frs_barriers_minimal(from)` |
| Bare descriptive nouns | `points`, `features`, `breaks`, `barrier_overrides` |
| No `_tbl` suffix on params | (only in internal vars) |

**Decision:** `from`/`to` for source/destination (matches existing fresh convention). `bridge` for the 3-way join intermediary (more explicit than `via`).

## Naming dissonance fixed

- Old: `table = streams_habitat`, `known = user_habitat_classification`
  - "known" presupposes provenance; function name was already `overlay` (mechanism), so param naming was inconsistent with function naming.
  - "table" was generic; could read as "the table being acted upon" but didn't clarify direction.
- New: `to = streams_habitat`, `from = user_habitat_classification`, `bridge = streams`
  - Reads as a sentence: "overlay flags from X to Y via this bridge"
  - Domain-agnostic: the bridge can be any segmented network, not just streams. Future: cottonwood polygons pinned to network, lake centerlines, wetland shorelines, anything that maps id_segment ↔ join keys.

## Bridge mechanism

**Without bridge** (NULL): direct point-match join `to.<by> = from.<by>` (equality on the join key columns). Works when target table has the geographic keys directly.

**With bridge**: 3-way join. Bridge provides id_segment + range columns:
- `to.id_segment = bridge.id_segment` (FK link)
- `bridge.<by[1]> = from.<by[1]>` (e.g. blue_line_key)
- `bridge.downstream_route_measure >= from.downstream_route_measure`
- `bridge.upstream_route_measure <= from.upstream_route_measure`

Range containment matters because user_habitat_classification rows define `[drm, urm]` ranges, and the lnk_pipeline_break habitat_endpoints step ensures fresh.streams has segments WITHIN those ranges (one or more per user_habitat row). The overlay needs to flag ALL fresh segments contained in the user_habitat range.
