#!/usr/bin/env bash
# Full loader run for #324 into a second instance on an empty data directory.
# Run from the repo root:  bash data-raw/logs/docker_rebuild_324/run.sh <fwapg dir>
# Writes beside itself: launch_utc.txt, stamp.txt, loader.log, disk.tsv and,
# last, loader.done holding the loader's exit status.
set -uo pipefail
# Changed after attempt 3 ran (code review, 2026-11-26): the fwapg path is made
# absolute, and the image is exported so a docker/.env cannot replace it.
FWAPG=$(cd "${1:?fwapg checkout to load from}" && pwd) || exit 1
IMAGE=${FRESH_DB_IMAGE:-imresamu/postgis:17-3.6.1-trixie}
L=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$L/../../.." && pwd)
export FRESH_DB_IMAGE="$IMAGE" FRESH_DB_CONTAINER=fresh-db-rebuild FRESH_LOADER_CONTAINER=fresh-loader-rebuild \
  FRESH_DB_PORT=5433 FRESH_DB_DATA=./postgres-data-rebuild FWAPG_DIR="$FWAPG"
DC=(docker compose -p fresh-rebuild -f "$REPO/docker/docker-compose.yml" -f "$L/second.yml")
FLOOR_G=${FLOOR_G:-30}

rm -f "$L/loader.done"
date -u +%FT%TZ > "$L/launch_utc.txt"
{
  echo "fresh: $(git -C "$REPO" rev-parse HEAD)"
  echo "fwapg: $(git -C "$FWAPG" rev-parse HEAD) ($(basename "$FWAPG"))"
  echo "image: $("${DC[@]}" config --images db 2>/dev/null | head -1)"
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

# compose `run` ignores container_name, so name it here: the watchdog stops it by name.
"${DC[@]}" run --rm --name fresh-loader-rebuild loader >> "$L/loader.log" 2>&1
rc=$?
echo "$rc" > "$L/loader.done"
exit "$rc"
