# Findings — fresh#158

## Diagnosis (2026-05-01)

bcfishpass's per-species rear rule has an inline OR clause:

```sql
(cw.channel_width >= t.rear_channel_width_min OR
 (s.stream_order_parent >= 5 AND s.stream_order = 1))
```

at [`bcfishpass/model/02_habitat_linear/sql/load_habitat_linear_bt.sql`](https://github.com/smnorris/bcfishpass/blob/main/model/02_habitat_linear/sql/load_habitat_linear_bt.sql) lines 89–96 (BT — same pattern in CH/CO/ST/WCT). Direct order-1 tributaries of order-5+ mainstems get credited as rearing **even when cw < rear_min**.

Biology: small tribs of large rivers support juvenile rearing despite small FWA-measured channel width — parent supplies flow / temperature / access; cool tributary water mixes at confluence; backwater + off-channel habitat near the mouth is high-value.

fresh has no implementation. link's `dimensions.csv::rear_stream_order_bypass = no` for all species in both bundles (correctly anticipating fresh has nothing to read). Provincial parity baseline (link 0.20.1) shows this gap on HORS / COLR / KHOR / CLRH / etc — Class B in `link/research/provincial_parity_2026_05_01.md`.

## Function design (per issue body)

`frs_order_child(conn, table, habitat, species, label = "rearing", parent_order_min = 5, child_order_min = NULL, child_order_max = NULL, distance_max = NULL)`

Post-classification UPDATE:

```sql
UPDATE habitat
SET <label> = TRUE
FROM streams s
WHERE habitat.id_segment = s.id_segment
  AND habitat.species_code = '<species>'
  AND habitat.accessible = TRUE
  AND habitat.<label> IS NOT TRUE
  AND s.stream_order = s.stream_order_max         -- direct child
  AND s.stream_order_parent >= <parent_order_min> -- of large river
  AND s.stream_order >= <child_order_min>         -- if set
  AND s.stream_order <= <child_order_max>         -- if set
  AND (<distance_max> IS NULL OR
       s.downstream_route_measure <= <distance_max>);
```

Direct-child filter: `s.stream_order = s.stream_order_max` ensures we stop at the order-change point (once the segment's order would exceed `stream_order_max`, you're no longer on the direct-child reach). Captures "small tributary directly into a large parent."

`accessible = TRUE` guard: never adds rearing on segments above a definite barrier.

`<label> IS NOT TRUE` guard: idempotent + additive — already-classified segments untouched.

## Pre vs post cluster — design decision (post-cluster wins)

bcfishpass embeds the bypass in the rule predicate (pre-cluster). Issue body's analysis: post-cluster is cleaner because:
- Bypassed segments don't need to pass connectivity (they're connected to the large parent by definition; the biology of the bypass IS the connectivity)
- `accessible = TRUE` already gates barrier-blocked reaches
- Post-cluster matches the parametric form (function takes WSG/species and applies, not a rule predicate that needs SQL grammar in fresh)
- Same end-state numbers as bcfp on the BCFP-parity caller-side defaults

## Caller defaults (link side, separate PR)

- bcfishpass bundle: `frs_order_child(species, parent_order_min = 5)` (defaults) for BT/CH/CO/ST/WCT
- default bundle: methodology-pending. Could ship same as bcfp first, tune later

## Versions at start

- fresh main: 253abf2 (0.26.0)
- link main: 9643be5 (0.21.0)
- bcfishpass: 440bc1e
