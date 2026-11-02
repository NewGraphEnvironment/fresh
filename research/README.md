# Research

What is known, kept beyond the issue that found it. One file per topic, named `<subject>_<aspect>.md`; revise the existing file rather than adding a dated one.

| file | topic |
|---|---|
| [fwa_waterbody_key_polygons.md](fwa_waterbody_key_polygons.md) | `waterbody_key` spans several polygons in `fwa_wetlands_poly`; how area floors test it |
| [fwapg_channel_width.md](fwapg_channel_width.md) | why first-order streams have no channel width; how fwapg's MODELLED width aggregates area; segments with no inputs |
| [fwa_point_snap.md](fwa_point_snap.md) | candidate rules of `fwa_indexpoint()` vs lateral KNN snaps; the positional tie rule and why it is ordered on the raw measure; `999.*` placeholder codes; the whole-metre measure formula; PSCIS parity; what fwapg#41 changes on fresh |
| [fwa_downstream_walk.md](fwa_downstream_walk.md) | what `FWA_Downstream()` and the working table give a downstream walk: code anomalies, rows with no local code, side-line connectors, gaps, prefilter safety; which features a downstream walk can reach and why the AOI's segments go in a temp table before the walk (#272); what an existence walk saves and why it is a join, not a correlated `EXISTS` (#281) |
| [id_segment_identity.md](id_segment_identity.md) | the two sites that assign `id_segment` and the two meanings they give it: base rows take `linear_feature_id`, only broken rows are derived — while `fresh.streams` holds a per-group 1..n sequence from an earlier pipeline, so a rule written from either artifact is wrong about the other; which delete key a partition overwrite may use, and why the parent segment is the only one correct against both artifacts; the unique index every persisted streams table carries and why a data-modifying CTE is not an atomic overwrite (#282, #293) |
| [fwa_upstream_predicate.md](fwa_upstream_predicate.md) | what each arity of `FWA_Upstream()` compares: the 4-arg form admits equality so same-wscode segments are mutually upstream regardless of position, the 8-arg form uses measures and excludes self, and `subpath()` on a one-label wscode is the empty ltree, which every code descends from (#242) |
| [fwa_fetch_determinism.md](fwa_fetch_determinism.md) | what makes a fetch repeat: row order on the FWA unique keys, simplifying lines without `ST_Normalize()` (it reverses them), lines vs polygons across GEOS versions, and how a key or measure must be written into SQL to reach the right segment (#286) |
