# Task: rename overlay params + add bridge support (#174)

Pre-1.0 cleanup driven by review of v0.20.0:
- Rename `table` → `to` (matches fresh's "destination" convention)
- Rename `known` → `from` (matches fresh's "source" convention; also detaches from "known habitat" provenance framing — function is the abstract "overlay" mechanism)
- Add `bridge = NULL` — when supplied, do 3-way join with range containment so target tables keyed by `id_segment` (e.g. `fresh.streams_habitat`) can be overlaid from sources keyed by `(blue_line_key, drm)` or any other geographic key.

After this lands, function reads as a sentence: **"overlay flags `from` X `to` Y `bridge` Z"** for any kind of segmented network — streams today, lakes/wetlands/cottonwood-pinned-to-segments tomorrow.

## Phases

- [ ] Phase 1 — PWF baseline
- [ ] Phase 2 — Param rename: `table` → `to`, `known` → `from`. Update R, tests, docs, NEWS. No deprecation alias (pre-1.0).
- [ ] Phase 3 — Add `bridge = NULL` parameter. When NULL, behave as today (direct point-match join). When non-NULL, do 3-way join with range containment.
- [ ] Phase 4 — Update SQL builders (both wide + long format) to support bridge mode.
- [ ] Phase 5 — Tests for bridge: range containment, NULL = unchanged behavior, missing range columns error, integration test with real fixture.
- [ ] Phase 6 — `/code-check` on diff
- [ ] Phase 7 — Full suite via rtj harness
- [ ] Phase 8 — NEWS + version bump → 0.21.0
- [ ] Phase 9 — PR, fix #174

## Bridge SQL shape

```sql
UPDATE <to> AS h
SET <hab> = TRUE
FROM <bridge> AS s, <from> AS k
WHERE h.id_segment = s.id_segment
  AND s.<by[1]> = k.<by[1]>            -- e.g. blue_line_key
  AND s.downstream_route_measure >= k.downstream_route_measure
  AND s.upstream_route_measure   <= k.upstream_route_measure
  AND <species/habitat filters>
  AND <additive guard>
```

Range-containment is the key: the bridge segment's [drm, urm] must lie within the source's [drm, urm].

## Acceptance

- All existing wide-format tests still pass with renamed params
- Long-format tests still pass
- New bridge tests cover: 3-way join range containment, integration with realistic fixture, error when bridge keys mismatch
- Full suite green
- `/code-check` signed off

## Risks

- **Breaking change** on `table` and `known` arg names. Pre-1.0, no deprecation alias. Link side already on a parked branch (`55-call-frs-habitat-overlay`) — will need to update arg names there too.
- **Range containment vs point match** is semantically distinct. `via = NULL` keeps point-match semantics; `via = "..."` opts into range. Document clearly.
