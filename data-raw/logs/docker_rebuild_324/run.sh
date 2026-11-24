#!/usr/bin/env bash
# Full loader run for #324 into a second instance on an empty data directory.
# Run from the repo root:  bash data-raw/logs/docker_rebuild_324/run.sh <fwapg dir>
# Writes beside itself: launch_utc.txt, stamp.txt, loader.log, disk.tsv and,
# last, loader.done holding the loader's exit status.
set -uo pipefail
FWAPG=${1:?fwapg checkout to load from}
L=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$L/../../.." && pwd)
export FRESH_DB_CONTAINER=fresh-db-rebuild FRESH_LOADER_CONTAINER=fresh-loader-rebuild \
  FRESH_DB_PORT=5433 FRESH_DB_DATA=./postgres-data-rebuild FWAPG_DIR="$FWAPG"
DC=(docker compose -p fresh-rebuild -f "$REPO/docker/docker-compose.yml" -f "$L/second.yml")
FLOOR_G=${FLOOR_G:-30}

rm -f "$L/loader.done"
date -u +%FT%TZ > "$L/launch_utc.txt"
{
  echo "fresh: $(git -C "$REPO" rev-parse HEAD)"
  echo "fwapg: $(git -C "$FWAPG" rev-parse HEAD) ($FWAPG)"
  echo "image: $(grep -E '^ +image:' "$REPO/docker/docker-compose.yml" | awk '{print $2}')"
} > "$L/stamp.txt"

[ ! -e "$REPO/docker/postgres-data-rebuild" ] || { echo "docker/postgres-data-rebuild exists: not an empty volume" >&2; echo 90 > "$L/loader.done"; exit 90; }

"${DC[@]}" up -d --wait db > "$L/loader.log" 2>&1 || { echo 91 > "$L/loader.done"; exit 91; }
echo "db: $(docker exec fresh-db-rebuild psql -U postgres -d fwapg -AtXc 'select postgis_full_version()')" >> "$L/stamp.txt"

# Disk watchdog: stop the loader if the disk falls below FLOOR_G GB free.
(
  while :; do
    a=$(df -Pk "$REPO" | awk 'NR == 2 {print int($4 / 1048576)}')
    printf '%s\tavail_G=%s\n' "$(date -u +%FT%TZ)" "$a" >> "$L/disk.tsv"
    if [ "$a" -lt "$FLOOR_G" ]; then
      echo "WATCHDOG: ${a} GB free < ${FLOOR_G}; stopping the loader" >> "$L/loader.log"
      docker stop fresh-loader-rebuild >/dev/null 2>&1
      exit 0
    fi
    sleep 120
  done
) &
WD=$!
trap 'kill "$WD" 2>/dev/null' EXIT

"${DC[@]}" run --rm loader >> "$L/loader.log" 2>&1
rc=$?
echo "$rc" > "$L/loader.done"
exit "$rc"
