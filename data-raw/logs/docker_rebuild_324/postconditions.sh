#!/bin/bash
# Post-conditions for the #324 rebuild (container fresh-db-rebuild, image
# 17-3.6.1-trixie, fwapg newgraph with its migrations) compared with the live
# fresh-db (17-3.5-bullseye, fwapg loaded months earlier, so row counts may
# drift). Adapted from data-raw/logs/docker_load_253/postconditions.sh.
# Usage, from the repo root:
#   bash data-raw/logs/docker_rebuild_324/postconditions.sh > data-raw/logs/docker_rebuild_324/postconditions.txt
# CONTAINERS overrides the pair, e.g. CONTAINERS=fresh-db for the live half alone.
set -uo pipefail

CONTAINERS=${CONTAINERS:-"fresh-db fresh-db-rebuild"}
q() { docker exec "$1" psql -U postgres -d fwapg -v ON_ERROR_STOP=1 -AtX -F $'\t' -c "$2"; }

# A probe prints its result rows (up to 20), or its first ERROR line, and the run
# continues. Anything else (no row, a psql or docker failure) prints
# "NO RESULT:" and the first line of output, so no probe drops out.
probe() {
  local out line
  out=$(q "$1" "$2" 2>&1) || true
  line=$(printf '%s\n' "$out" | grep -E '^ERROR|	' | head -20 || true)
  [ -n "$line" ] || line="NO RESULT: $(printf '%s\n' "$out" | grep -m1 . || echo 'no output')"
  printf '%s\n' "$line"
}

for c in $CONTAINERS; do
  echo "## $c: versions"
  probe "$c" "select 'server', current_setting('server_version')"
  probe "$c" "select 'postgis_full_version', postgis_full_version()"
  probe "$c" "select 'extension', extname, extversion from pg_extension order by extname"
  probe "$c" "select 'collation', datcollate, coalesce(datcollversion, '') from pg_database where datname = 'fwapg'"
  probe "$c" "select 'fwapg.db_version', tag from fwapg.db_version"
  probe "$c" "select 'search_path', array_to_string(s.setconfig, ';') from pg_db_role_setting s join pg_database d on d.oid = s.setdatabase where d.datname = 'fwapg'"
  probe "$c" "select 'fwa_indexpoint args', pg_get_function_arguments('whse_basemapping.fwa_indexpoint'::regproc)"
  probe "$c" "select 'fwa_watershedatmeasure mentions exbc', p.prosrc ~* 'exbc' from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'whse_basemapping' and p.proname = 'fwa_watershedatmeasure'"
  echo
done

echo "## row counts: table, then one count per container ($CONTAINERS), pct_diff of the second against the first"
tables="whse_basemapping.fwa_stream_networks_sp whse_basemapping.fwa_streams
whse_basemapping.fwa_lakes_poly whse_basemapping.fwa_wetlands_poly
whse_basemapping.fwa_rivers_poly whse_basemapping.fwa_manmade_waterbodies_poly
whse_basemapping.fwa_watersheds_poly whse_basemapping.fwa_assessment_watersheds_poly
whse_basemapping.fwa_watershed_groups_poly whse_basemapping.fwa_named_streams
whse_basemapping.fwa_stream_networks_channel_width whse_basemapping.fwa_stream_networks_discharge
whse_basemapping.fwa_stream_networks_order_parent whse_basemapping.fwa_streams_watersheds_lut
whse_basemapping.pcic_fwa_crosswalk whse_basemapping.fwa_stream_networks_discharge_monthly
working.falls working.crossings"
for t in $tables; do
  row="$t"
  first=
  for c in $CONTAINERS; do
    n=$(q "$c" "select count(*) from $t" 2>/dev/null || echo NA)
    row="$row	$n"
    if [ -z "$first" ]; then first=$n; else second=$n; fi
  done
  pct=NA
  if [ -n "${second:-}" ] && [ "$first" != NA ] && [ "$second" != NA ] && [ "$first" -gt 0 ]; then
    pct=$(awk -v a="$first" -v b="$second" 'BEGIN { printf "%.3f", 100 * (b - a) / a }')
  fi
  printf '%s\t%s\n' "$row" "$pct"
  unset second
done

# #304: streams the lut is built for (load/fwa_streams_watersheds_lut.sql's
# filters) and how many have a row. BULK + ADMS expected 40,504 on #304's count.
lut_cover="from whse_basemapping.fwa_stream_networks_sp s
  left join whse_basemapping.fwa_streams_watersheds_lut l using (linear_feature_id)
  where s.fwa_watershed_code not like '999%' and s.local_watershed_code is not null
  and s.edge_type != 6100"

# Functions whose bodies call other fwa functions unqualified, and the
# unqualified fwa_upstream() form fresh's SQL uses (R/frs_classify.R).
# Each runs in a new session, so only the database search_path applies.
blk=360873822
drm=166030
# A lake point takes the function's other branch (360457111 is a BULK lake line).
lake_blk=360457111
lake_drm=924.5
for c in $CONTAINERS; do
  echo
  echo "## $c: lut coverage (#304)"
  probe "$c" "select 'BULK+ADMS streams, with lut row, missing', count(*), count(l.linear_feature_id), count(*) - count(l.linear_feature_id) $lut_cover and s.watershed_group_code in ('BULK', 'ADMS')"
  probe "$c" "select 'province streams, with lut row, missing', count(*), count(l.linear_feature_id), count(*) - count(l.linear_feature_id) $lut_cover"
  echo
  echo "## $c: functions"
  probe "$c" "select 'fwa_watershedatmeasure', round(area_ha::numeric, 1) from whse_basemapping.fwa_watershedatmeasure($blk, $drm)"
  probe "$c" "select 'postgisftw.fwa_watershedatmeasure', round(area_ha::numeric, 1) from postgisftw.fwa_watershedatmeasure($blk, $drm)"
  probe "$c" "select 'fwa_watershedatmeasure lake', round(area_ha::numeric, 1) from whse_basemapping.fwa_watershedatmeasure($lake_blk, $lake_drm)"
  probe "$c" "select 'fwa_downstreamtrace', count(*), round(sum(length_metre)::numeric) from whse_basemapping.fwa_downstreamtrace($blk, $drm)"
  probe "$c" "select 'fwa_upstream unqualified', count(*) from whse_basemapping.fwa_stream_networks_sp s, (select wscode_ltree, localcode_ltree from whse_basemapping.fwa_stream_networks_sp where blue_line_key = $blk and downstream_route_measure <= $drm order by downstream_route_measure desc limit 1) r where s.watershed_group_code = 'BULK' and fwa_upstream(r.wscode_ltree, r.localcode_ltree, s.wscode_ltree, s.localcode_ltree)"
done
