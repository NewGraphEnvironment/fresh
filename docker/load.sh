#!/bin/bash
# Load fwapg data into the local Docker PostGIS instance.
#
# Runs inside the loader container. Volumes mounted by docker-compose:
#   /home/fwapg      — smnorris/fwapg repo (read-only)
#   /home/bcfishobs  — smnorris/bcfishobs repo (read-only, optional)
#   /home/fresh/extdata — fresh inst/extdata (read-only)
#
# Usage (from docker/):
#   docker compose run --rm loader              # fwapg + falls
#   docker compose run --rm loader --bcfishobs   # + fish observations

set -euo pipefail

FWAPG_DIR="/home/fwapg"
BCFISHOBS_DIR="/home/bcfishobs"
EXTDATA_DIR="/home/fresh/extdata"

PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"

# ---------------------
# Validate
# ---------------------
if [ ! -d "$FWAPG_DIR/db" ]; then
  echo "ERROR: fwapg repo not mounted at $FWAPG_DIR"
  echo "Set FWAPG_DIR env var in docker-compose.yml"
  exit 1
fi

echo "=== fresh local DB loader ==="
echo "  fwapg:    $FWAPG_DIR"
echo "  database: $DATABASE_URL"
echo ""

# ---------------------
# Stage 1: fwapg schema + functions
# ---------------------
echo "--- Stage 1: fwapg schema + functions ---"

# fwapg's create.sh uses relative paths, so we need to cd
# but it's read-only, so copy the db scripts to a writable temp dir
WORK_DIR=$(mktemp -d)
cp -r "$FWAPG_DIR/db" "$WORK_DIR/db"
cp -r "$FWAPG_DIR/load.sh" "$WORK_DIR/load.sh"
cp -r "$FWAPG_DIR/load" "$WORK_DIR/load"
[ -d "$FWAPG_DIR/fixes" ] && cp -r "$FWAPG_DIR/fixes" "$WORK_DIR/fixes"
[ -f "$FWAPG_DIR/.env.docker" ] && cp "$FWAPG_DIR/.env.docker" "$WORK_DIR/.env.docker"

cd "$WORK_DIR/db"
bash create.sh
echo ""

# ---------------------
# Stage 2: fwapg data
# ---------------------
echo "--- Stage 2: fwapg data (this takes a while) ---"
cd "$WORK_DIR"
bash load.sh
echo ""

# ---------------------
# Stage 3: working schema + falls from CSV
# ---------------------
echo "--- Stage 3: fresh working schema + falls ---"
$PSQL -c "CREATE SCHEMA IF NOT EXISTS working"

FALLS_CSV="$EXTDATA_DIR/falls.csv"
if [ -f "$FALLS_CSV" ]; then
  echo "Loading falls from $FALLS_CSV"
  $PSQL -c "DROP TABLE IF EXISTS working.falls"
  $PSQL -c "CREATE TABLE working.falls (
    blue_line_key integer,
    downstream_route_measure double precision,
    watershed_group_code character varying(4),
    falls_name text,
    height_m double precision,
    barrier_ind boolean
  )"
  $PSQL -c "\copy working.falls FROM '$FALLS_CSV' delimiter ',' csv header"
  echo "  Loaded $($PSQL -AtX -c 'SELECT count(*) FROM working.falls') falls"
else
  echo "WARNING: $FALLS_CSV not found — skipping falls load"
  echo "  Run data-raw/bcfishpass_falls.R to generate it"
fi

# ---------------------
# Stage 4 (optional): bcfishobs
# ---------------------
if [[ "${1:-}" == "--bcfishobs" ]]; then
  if [ ! -d "$BCFISHOBS_DIR/sql" ]; then
    echo "ERROR: bcfishobs repo not mounted at $BCFISHOBS_DIR"
    echo "Set BCFISHOBS_DIR env var in docker-compose.yml"
    exit 1
  fi

  echo "--- Stage 4: bcfishobs ---"
  # bcfishobs Makefile uses relative paths + writes data/
  BCFISH_WORK=$(mktemp -d)
  cp -r "$BCFISHOBS_DIR"/* "$BCFISH_WORK/"
  cd "$BCFISH_WORK"
  make all
  echo ""
fi

# ---------------------
# Cleanup
# ---------------------
rm -rf "$WORK_DIR" "${BCFISH_WORK:-/dev/null}" 2>/dev/null || true

echo "=== Done ==="
echo ""
echo "Connect from R:"
echo '  conn <- DBI::dbConnect(RPostgres::Postgres(),'
echo '    host = "localhost", port = 5432,'
echo '    dbname = "fwapg", user = "postgres", password = "postgres")'
