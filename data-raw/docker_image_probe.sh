#!/usr/bin/env bash
# Probe candidate PostGIS images for the GEOS answers fresh depends on (#324).
#
# Copies the geometries of #304 (three streams and their watersheds) and #306
# (Tahtsa Reach, waterbody_poly_id 700228651) out of a running local fwapg as
# EWKB, then runs the same probes on that database and on a throwaway
# container of each image given:
#   boundary   the midpoint of each stream, which ST_Relate puts on its
#              watershed's boundary: ST_Intersects, ST_Covers, ST_Contains,
#              ST_DWithin(0) and the DE-9IM matrix
#   vertical   the intersection of a box with a vertical line inside it
#   simplify   ST_NPoints(ST_SimplifyPreserveTopology(lake, 100)), 20 times in
#              one session (#306)
#
# Usage (from the repo root):
#   bash data-raw/docker_image_probe.sh <source container> <db> <image>... > <log>
#   bash data-raw/docker_image_probe.sh fresh-db fwapg \
#     imresamu/postgis:17-3.5.3-bookworm imresamu/postgis:17-3.6.1-trixie \
#     > data-raw/logs/docker_rebuild_324/image_probe.txt
# An image may carry a platform after `::`, passed to `docker run --platform`:
#   bash data-raw/docker_image_probe.sh fresh-db fwapg postgis/postgis:16-3.5::linux/amd64 \
#     > data-raw/logs/docker_rebuild_324/image_probe_amd64.txt
# Without one, Docker runs the host's platform, and an image without it fails
# unless an other-platform copy is already cached.
#
# Each image runs as a container named probe-<n>, with no port published, and
# is stopped (and removed) on exit.

set -euo pipefail

[ "$#" -ge 3 ] || { echo "usage: $0 <source container> <db> <image>..." >&2; exit 1; }
SRC=$1; DB=$2; shift 2

TMP=$(mktemp -d "${TMPDIR:-/tmp}/image_probe.XXXXXX")
STARTED=()
cleanup() {
  for c in ${STARTED[@]+"${STARTED[@]}"}; do docker stop "$c" >/dev/null 2>&1 || true; done
  rm -rf "$TMP"
}
trap cleanup EXIT

docker exec "$SRC" psql -U postgres -d "$DB" -AtX -v ON_ERROR_STOP=1 -c "
COPY (
 SELECT 'stream', linear_feature_id::text, encode(ST_AsEWKB(geom), 'hex')
 FROM whse_basemapping.fwa_stream_networks_sp
 WHERE linear_feature_id IN (17046241, 700244339, 700277597)
 UNION ALL
 SELECT 'ws', watershed_feature_id::text, encode(ST_AsEWKB(geom), 'hex')
 FROM whse_basemapping.fwa_watersheds_poly
 WHERE watershed_feature_id IN (7637979, 7630925, 7607864)
 UNION ALL
 SELECT 'lake', waterbody_poly_id::text, encode(ST_AsEWKB(geom), 'hex')
 FROM whse_basemapping.fwa_lakes_poly
 WHERE waterbody_poly_id = 700228651
) TO STDOUT" > "$TMP/geoms.tsv"
n=$(wc -l < "$TMP/geoms.tsv")
[ "$n" -eq 7 ] || { echo "expected 7 geometries from $SRC, got $n" >&2; exit 1; }

{
  echo "\\pset footer off"
  echo "CREATE TEMP TABLE g (kind text, id bigint, geom geometry);"
  echo "COPY g FROM STDIN;"
  cat "$TMP/geoms.tsv"
  echo "\\."
  echo "SELECT postgis_full_version();"
  echo "SELECT s.id AS stream, w.id AS ws,
    ST_Distance(p, w.geom) AS dist,
    ST_Intersects(p, ST_Boundary(w.geom)) AS on_boundary,
    ST_Intersects(p, w.geom) AS intersects,
    ST_Covers(w.geom, p) AS covers,
    ST_Contains(w.geom, p) AS contains,
    ST_DWithin(p, w.geom, 0) AS dwithin0,
    ST_Relate(p, w.geom) AS de9im
  FROM (SELECT id, ST_LineInterpolatePoint(geom, .5) AS p FROM g WHERE kind = 'stream') s
  JOIN (VALUES (17046241, 7637979), (700244339, 7630925), (700277597, 7607864)) v(sid, wid)
    ON v.sid = s.id
  JOIN g w ON w.kind = 'ws' AND w.id = v.wid
  ORDER BY s.id;"
  echo "SELECT x AS line_x, ST_AsText(ST_Intersection(l, b)) AS intersection, ST_Contains(b, l) AS box_contains_line
  FROM (SELECT x, ST_MakeLine(ST_Point(x, 0), ST_Point(x, -100)) AS l,
               ST_MakeEnvelope(-10, -150, 2100, 100) AS b
        FROM (VALUES (1000), (1500)) v(x)) q ORDER BY x;"
  echo "CREATE TEMP TABLE simp (i int, n int);"
  for i in $(seq 1 20); do
    echo "INSERT INTO simp SELECT $i, ST_NPoints(ST_SimplifyPreserveTopology(geom, 100)) FROM g WHERE kind = 'lake';"
  done
  echo "SELECT n AS simplify_100_npoints, count(*) AS calls FROM simp GROUP BY n ORDER BY n;"
} > "$TMP/probe.sql"

run_probe() {  # container db label
  echo "===== $3"
  docker exec -i "$1" psql -U postgres -d "$2" -X -q -v ON_ERROR_STOP=1 < "$TMP/probe.sql"
  echo
}

echo "# docker_image_probe.sh, $(date -u +%FT%TZ)"
echo "# source: $SRC/$DB ($(docker inspect "$SRC" --format '{{.Config.Image}}'))"
echo
run_probe "$SRC" "$DB" "$SRC (source database)"

i=0
for spec in "$@"; do
  i=$((i + 1)); c="probe-$i-$$"
  img=${spec%%::*}
  plat=()
  [ "$img" = "$spec" ] || plat=(--platform "${spec#*::}")
  docker run -d --rm --name "$c" ${plat[@]+"${plat[@]}"} -e POSTGRES_PASSWORD=probe "$img" >/dev/null
  STARTED+=("$c")
  # The image's init runs a temporary server on the Unix socket only, creates
  # the postgis extension there, then restarts: wait for TCP (the real server)
  # and the extension, or psql can land on the temporary server as it stops.
  for _ in $(seq 1 400); do
    docker exec "$c" pg_isready -U postgres -h 127.0.0.1 -q 2>/dev/null \
      && docker exec "$c" psql -U postgres -h 127.0.0.1 -AtXc \
           "SELECT 1 FROM pg_extension WHERE extname = 'postgis'" 2>/dev/null | grep -q 1 \
      && break
    sleep 3
  done
  run_probe "$c" postgres "$spec ($(docker image inspect "$img" --format '{{index .RepoDigests 0}}'))"
done
