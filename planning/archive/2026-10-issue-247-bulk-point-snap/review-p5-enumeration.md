# Phase 5 code-check — enumeration (terminal step)

Round 2 found defects inside round 1's fixes (the "rounded down" rewording;
`true`/`false` key normalisation missing `t`/`f`), so the loop ends on an
enumeration.

## Mechanism A — a prose description of the snap that drifts from the SQL

Every claim about measure / candidates / cost in docs
(`grep -n "whole metre|measure is|round trip|rounded|never candidates|snap to everything"`
over NEWS.md, CLAUDE.md, R/frs_point_snap.R, R/frs_feature_find.R,
R/frs_watershed_split.R):

| place | claim | matches SQL |
|---|---|---|
| NEWS.md:6 | "one snap query, not 1,000" | yes (snap is one statement; temp write / drop are fixed overhead) |
| NEWS.md:10 | whole metre, rounded down, never below start rounded up; 999.* / unmapped never; 1425 by default; 6010 a candidate | yes |
| NEWS.md:18 | watershed_split: whole metres; no 1425 / 999 / unmapped; 6010 possible | yes |
| CLAUDE.md:226 | NULL exclude_edge_types: placeholder / unmapped still excluded | yes |
| CLAUDE.md:234 | formula verbatim + vertex tie + sub-metre segment overrun | yes |
| R/frs_point_snap.R:8 | "one snap query" | yes |
| R/frs_point_snap.R:12 | `999.*` / unmapped never (was `999`) | fixed |
| R/frs_point_snap.R:13-17 | whole metre per bcfishpass formula | yes |
| R/frs_point_snap.R:58 | `exclude_edge_types` default / NULL | yes |
| R/frs_point_snap.R:379 | internal: "clamped to the segment's own range" | fixed → formula reference |

10 of 10 consistent.

## Mechanism B — label_map key in R's spelling vs PostgreSQL's `::text`

Types a `label_col` plausibly has, natural key vs `::text` (round 2,
verified on fwapg): text / varchar / factor, smallint / integer / bigint,
date, enum / bpchar — match. boolean — `::text` is `true`/`false`; R
displays `TRUE`, psql `t`: both now normalised (`lower(col::text) IN (key,
canon)`). Remaining boolean input spellings (`yes`/`no`, `on`/`off`, `y`/`n`,
`1`/`0`) are not what R or psql display, so a user would not derive them
from the data; the accepted keys are documented on `label_map`. double /
numeric with scale / timestamptz mismatch only on unnatural keys (implausible
as labels, round 2).
