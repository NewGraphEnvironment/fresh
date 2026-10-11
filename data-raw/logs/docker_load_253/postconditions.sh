#!/bin/bash
# Post-conditions for the #253 loader run into fwapg_253, compared with the
# live fwapg (loaded months earlier, so row counts may drift).
# Usage: bash postconditions.sh > postconditions.txt
set -euo pipefail

q() { docker exec fresh-db psql -U postgres -d "$1" -v ON_ERROR_STOP=1 -AtX -F $'\t' -c "$2"; }

echo "## search_path (database setting)"
docker exec fresh-db psql -U postgres -AtX -c "select d.datname, s.setconfig from pg_db_role_setting s join pg_database d on d.oid = s.setdatabase where d.datname in ('fwapg', 'fwapg_253') order by 1"

echo
echo "## row counts: table, fwapg, fwapg_253, pct_diff"
tables="whse_basemapping.fwa_stream_networks_sp whse_basemapping.fwa_streams
whse_basemapping.fwa_lakes_poly whse_basemapping.fwa_wetlands_poly
whse_basemapping.fwa_rivers_poly whse_basemapping.fwa_watersheds_poly
whse_basemapping.fwa_assessment_watersheds_poly whse_basemapping.fwa_watershed_groups_poly
whse_basemapping.fwa_stream_networks_channel_width whse_basemapping.fwa_stream_networks_discharge
whse_basemapping.fwa_stream_networks_order_parent whse_basemapping.fwa_streams_watersheds_lut
whse_basemapping.pcic_fwa_crosswalk whse_basemapping.fwa_stream_networks_discharge_monthly
working.falls working.crossings"
for t in $tables; do
  a=$(q fwapg "select count(*) from $t" 2>/dev/null || echo NA)
  b=$(q fwapg_253 "select count(*) from $t" 2>/dev/null || echo NA)
  if [ "$a" != NA ] && [ "$b" != NA ] && [ "$a" -gt 0 ]; then
    pct=$(awk -v a="$a" -v b="$b" 'BEGIN { printf "%.3f", 100 * (b - a) / a }')
  else
    pct=NA
  fi
  printf '%s\t%s\t%s\t%s\n' "$t" "$a" "$b" "$pct"
done

# Functions whose bodies call other fwa functions unqualified, and the
# unqualified fwa_upstream() form fresh's SQL uses (R/frs_classify.R).
# Each runs in a new session, so only the database search_path applies.
blk=360873822
drm=166030
for db in fwapg fwapg_253; do
  echo
  echo "## functions on $db"
  q "$db" "select 'fwa_watershedatmeasure', round(area_ha::numeric, 1) from whse_basemapping.fwa_watershedatmeasure($blk, $drm)"
  q "$db" "select 'fwa_downstreamtrace', count(*), round(sum(length_metre)::numeric) from whse_basemapping.fwa_downstreamtrace($blk, $drm)"
  q "$db" "select 'fwa_upstream unqualified', count(*) from whse_basemapping.fwa_stream_networks_sp s, (select wscode_ltree, localcode_ltree from whse_basemapping.fwa_stream_networks_sp where blue_line_key = $blk and downstream_route_measure <= $drm order by downstream_route_measure desc limit 1) r where s.watershed_group_code = 'BULK' and fwa_upstream(r.wscode_ltree, r.localcode_ltree, s.wscode_ltree, s.localcode_ltree)"
done
