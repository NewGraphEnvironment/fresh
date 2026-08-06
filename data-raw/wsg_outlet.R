#!/usr/bin/env Rscript
# wsg_outlet.R — regenerate inst/extdata/wsg_outlet.csv
#
# One row per FWA watershed group: the outlet POINT (blue_line_key +
# downstream_route_measure) plus its (wscode_ltree, localcode_ltree) pair.
# Consumed by frs_wsg_drainage() to compute drainage closure via
# whse_basemapping.fwa_downstream().
#
# WHY A POINT AND NOT JUST A CODE
#
# A single ltree cannot order two groups sharing a stem. Every Fraser group
# carries wscode `100`; five Skeena groups carry `400`. The four-argument
# ltree-only fwa_downstream() therefore returns FALSE for UFRA -> LFRA even
# though the Upper Fraser plainly drains through the Lower Fraser. The
# measure-aware overload resolves it: both sit on blue_line_key 356364114 at
# downstream_route_measure 0 and 1,189,576 respectively.
#
# WHY MAX STREAM ORDER FIRST
#
# Watershed group polygons clip slivers of neighbouring systems, so the
# shallowest wscode present in a group is not necessarily the stream that
# drains it. MORR (Morice) contains a 2-segment, 0 km, order-1 sliver of the
# Bulkley-coded line `400.431358` alongside 1,236 segments and 275 km of the
# order-8 Morice line `400.431358.585806`. Selecting on nlevel alone — as the
# ad-hoc `public.wsg_outlet` table did (link#227) — picks the sliver and makes
# the Bulkley appear to drain through the Morice. Filtering to the group's
# maximum stream order first eliminates slivers; nlevel then breaks the
# remaining tie correctly (in BULK both the Bulkley and a Morice sliver are
# order 8, and the shallower Bulkley code wins).
#
# Usage: Rscript data-raw/wsg_outlet.R
# Requires a connection to a database carrying whse_basemapping.

suppressPackageStartupMessages({
  library(DBI)
})

conn <- fresh::frs_db_conn()
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

sql <- "
WITH mx AS (
  SELECT watershed_group_code AS wsg, max(stream_order) AS mo
  FROM whse_basemapping.fwa_stream_networks_sp
  WHERE wscode_ltree IS NOT NULL AND localcode_ltree IS NOT NULL
  GROUP BY 1
)
SELECT DISTINCT ON (s.watershed_group_code)
       s.watershed_group_code AS watershed_group_code,
       s.blue_line_key,
       s.downstream_route_measure,
       s.wscode_ltree::text AS wscode_ltree,
       s.localcode_ltree::text AS localcode_ltree
FROM whse_basemapping.fwa_stream_networks_sp s
JOIN mx ON mx.wsg = s.watershed_group_code AND s.stream_order = mx.mo
WHERE s.wscode_ltree IS NOT NULL AND s.localcode_ltree IS NOT NULL
ORDER BY s.watershed_group_code,
         nlevel(s.wscode_ltree) ASC,
         s.downstream_route_measure ASC"

out <- DBI::dbGetQuery(conn, sql)
out <- out[order(out$watershed_group_code), ]
out$downstream_route_measure <- round(out$downstream_route_measure, 3)

stopifnot(
  nrow(out) > 0,
  !anyNA(out$watershed_group_code),
  !anyNA(out$blue_line_key),
  !anyNA(out$wscode_ltree),
  !anyNA(out$localcode_ltree),
  !any(duplicated(out$watershed_group_code))
)

path <- "inst/extdata/wsg_outlet.csv"
utils::write.csv(out, path, row.names = FALSE, quote = FALSE)
message(sprintf("[wsg_outlet] wrote %d rows to %s", nrow(out), path))
