# network_features_272

Before/after timings of `frs_network_features(direction = "downstream", aoi = <group>)`
for fresh#272, produced by `data-raw/network_features_prefilter.R` on 2026-10-28
(19:40-20:57 UTC), PostgreSQL 17.5, the local `docker/` fwapg, with no other client
backend active (`others_active` is 0 on every row).

- **Shape:** `segments = fresh_default.streams` (province-wide, 11.3 M rows) with `aoi`, the
  shape fresh documents. `features` = link's `fresh_default.barriers_ch_access`,
  `barriers_bt_access` and `barriers_anthropogenic_unified`, `include_equivalents = TRUE`.
- **Forms:** `old` is the SQL v0.44.0 sends. `new` is this branch: `ddl_seconds` is the
  temp table (copy, three indexes, `ANALYZE`), `walk_seconds` the prefiltered walk.
  `old_scoped` is the v0.44.0 SQL with `segments` swapped for an indexed, analyzed temp copy
  of the group (the shape link measured in link#261). It runs only when `old` timed out, so
  that every walk still has an oracle digest.
- **Order:** old, new, new, old per walk. Each statement has a 10-minute cap. When the first
  `old` run times out, the second is skipped (`d_set` reads `skipped: …`).
- **Digests:** link's `digest_sql`. `d_order` hashes each array in its returned order;
  `d_set` hashes the array sorted. `d_set` agrees across every form of every walk (12 of 12).
  `d_order` differs where the old SQL left ties to the plan (SALR CH, CHWK CH and BT
  `old_scoped`), which is the tie order the new `ORDER BY` key fixes.

## Results

Seconds; `new` is the mean of its two runs, DDL included.

| group (segments) | view | old | old_scoped | new | old / new |
|---|---|---|---|---|---|
| SALR (11,392) | CH | > 600 | 17.2 | 1.94 | > 309× |
| | BT | > 600 | 8.1 | 0.80 | > 746× |
| | anthropogenic | 1.11 | | 0.32 | 3.4× |
| LKEL (7,448) | CH | > 600 | 12.8 | 0.68 | > 888× |
| | BT | > 600 | 7.3 | 0.34 | > 1,775× |
| | anthropogenic | 0.85 | | 0.17 | 4.9× |
| CHWK (14,347) | CH | > 600 | 96.4 | 3.16 | > 190× |
| | BT | > 600 | 42.6 | 1.28 | > 470× |
| | anthropogenic | 1.19 | | 0.37 | 3.3× |
| LSKE (77,496) | CH | > 600 | 65.9 | 8.35 | > 72× |
| | BT | > 600 | 34.2 | 4.33 | > 138× |
| | anthropogenic | 4.51 | | 1.74 | 2.6× |

The temp table costs 0.07-0.14 s for the three smaller groups and 0.7 s for LSKE. On the
large views the old SQL never finished on the province-wide table, and the
`old_scoped` column (the scoped table without the prefilter) is 7.9× (LSKE) to 33×
(CHWK) slower than the new form.

`walks.tsv` columns: `wsg`, `features`, `form`, `rep`, `segments_out` (segments with at
least one downstream feature), `ddl_seconds`, `walk_seconds`, `seconds`, `timed_out`,
`d_order`, `d_set`, `others_active`, `measured_utc`.
