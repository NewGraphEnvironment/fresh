# FWA waterbody keys can span several polygons

Source: measured 2026-10-07 on fwapg (`whse_basemapping`), while working fresh#237. Query in the archive README of `planning/archive/2026-10-issue-237-wetland-floor-rear/`.

`waterbody_key` is not unique in the FWA polygon tables. Any per-key area test has to decide what "the wetland's area" means.

| table | keys | keys with > 1 polygon | max polygons per key | keys straddling 1 ha | keys straddling 0.5 ha |
|---|---|---|---|---|---|
| `fwa_wetlands_poly` | 333,526 | 19,510 | 1,688 | 6,730 | 3,085 |
| `fwa_lakes_poly` | 386,014 | 9 | 3 | 2 | 2 |

"Straddling" means the key has one polygon under the threshold and another at or over it. No key is NULL in either table.

**How fresh tests area.** A rule's floor compiles to `s.waterbody_key IN (SELECT waterbody_key FROM <poly> WHERE area_ha >= floor)`. That admits a key when **any** of its polygons meets the floor, not the summed or largest area.

**What that means for an analysis.** A query that asks "is this segment in a wetland under the floor?" must use the complement of the rule's test: a key with no polygon `>= floor`, i.e. `NOT EXISTS`. Writing `area_ha < floor` instead flags straddling keys the rule admits. For #237's measurement, that overcounted residual small-wetland rearing by 139 of 899 segments (NATR BT).
