# Live check for fresh#240: lake / wetland buckets sized by polygon area,
# then kept only where connected to same-species spawning.
#
# Reads one WSG of link's persisted `fresh_default` (streams +
# streams_habitat_<sp>) from the local fwapg, copies it to pg_temp, and
# reports bucket km and polygon counts for:
#   persisted  - as link last wrote them (size-gated, no connectivity)
#   area_only  - this branch's predicate (polygon membership + *_ha_min)
#   connected  - area_only, then .frs_bucket_connected() at each distance
# Spawning is the persisted spawning (already connectivity-filtered).
#
# Usage (from the fresh repo root):
#   Rscript data-raw/bucket_connected_check.R [WSG] [SPECIES] [DISTANCES]
#   Rscript data-raw/bucket_connected_check.R NATR BT 500,1000,3000,10000
# Writes data-raw/logs/bucket_connected_240/<wsg>_<sp>.csv and a .txt stamp.

pkgload::load_all(".", quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
wsg <- toupper(if (length(args) >= 1) args[[1]] else "NATR")
sp <- toupper(if (length(args) >= 2) args[[2]] else "BT")
distances <- as.numeric(strsplit(
  if (length(args) >= 3) args[[3]] else "500,1000,3000,10000", ",")[[1]])
stopifnot(grepl("^[A-Z]{4}$", wsg), grepl("^[A-Z]{2,3}$", sp),
          all(is.finite(distances)), all(distances > 0))

rules_path <- "~/Projects/repo/link/inst/extdata/configs/default/rules.yaml"
out_dir <- "data-raw/logs/bucket_connected_240"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

conn <- frs_db_conn()
q <- function(sql) DBI::dbGetQuery(conn, sql)
x <- function(sql) invisible(DBI::dbExecute(conn, sql))

hab_src <- sprintf("fresh_default.streams_habitat_%s", tolower(sp))
n <- q(sprintf("SELECT count(*)::int n FROM %s WHERE watershed_group_code = '%s'",
               hab_src, wsg))$n
if (n == 0) stop(sprintf("%s has no %s rows in %s", wsg, sp, hab_src))

x(sprintf(
  "CREATE TEMP TABLE chk_streams AS
   SELECT * FROM fresh_default.streams WHERE watershed_group_code = '%s'", wsg))
# The indexes .frs_index_working() gives a working table, and no more;
# .frs_bucket_connected() adds its own GiST on geom and ANALYZEs, so the
# trace timing is what the pipeline would see.
x("CREATE INDEX ON chk_streams (id_segment)")
x("CREATE INDEX ON chk_streams (blue_line_key)")
x("CREATE INDEX ON chk_streams USING gist (wscode_ltree)")
x("CREATE INDEX ON chk_streams USING gist (localcode_ltree)")
x("ANALYZE chk_streams")
x(sprintf(
  "CREATE TEMP TABLE chk_persisted AS
   SELECT id_segment, watershed_group_code, '%s'::text AS species_code,
          accessible, spawning,
          rearing, lake_rearing, wetland_rearing
   FROM %s WHERE watershed_group_code = '%s'", sp, hab_src, wsg))

# Area-only buckets from this branch's predicate and link's default rules
rules <- .frs_load_rules(path.expand(rules_path))[[sp]]
preds <- frs_habitat_predicates(list(species_code = sp,
  params_sp = list(ranges = list(), rules = rules)))
x(sprintf(
  "CREATE TEMP TABLE chk_area AS
   SELECT h.id_segment, h.watershed_group_code, h.species_code,
          h.accessible, h.spawning, h.rearing,
          (h.accessible AND (%s)) AS lake_rearing,
          (h.accessible AND (%s)) AS wetland_rearing
   FROM chk_persisted h JOIN chk_streams s ON s.id_segment = h.id_segment",
  preds$lake_rear, preds$wetland_rear))

summ <- function(habitat, label, d = NA, secs = NA) {
  r <- q(sprintf(
    "SELECT
       round((sum(s.length_metre) FILTER (WHERE h.lake_rearing) / 1000)::numeric, 1) lake_km,
       count(DISTINCT s.waterbody_key) FILTER (WHERE h.lake_rearing) lake_n,
       round((sum(s.length_metre) FILTER (WHERE h.wetland_rearing) / 1000)::numeric, 1) wetland_km,
       count(DISTINCT s.waterbody_key) FILTER (WHERE h.wetland_rearing) wetland_n
     FROM %s h JOIN chk_streams s ON s.id_segment = h.id_segment", habitat))
  cbind(data.frame(wsg = wsg, species = sp, state = label,
                   distance_m = d, seconds = secs), r)
}

rows <- list(summ("chk_persisted", "persisted"), summ("chk_area", "area_only"))
for (d in distances) {
  x("DROP TABLE IF EXISTS chk_conn")
  x("CREATE TEMP TABLE chk_conn AS SELECT * FROM chk_area")
  x("CREATE INDEX ON chk_conn (id_segment)")
  t0 <- proc.time()[["elapsed"]]
  for (col in c("lake_rearing", "wetland_rearing")) {
    .frs_bucket_connected(conn, "pg_temp.chk_streams", "pg_temp.chk_conn",
      species = sp, column = col, distance_max = d, verbose = FALSE)
  }
  secs <- round(proc.time()[["elapsed"]] - t0, 1)
  rows[[length(rows) + 1]] <- summ("chk_conn", "connected", d, secs)
}
res <- do.call(rbind, rows)
print(res, row.names = FALSE)

stem <- file.path(out_dir, sprintf("%s_%s", tolower(wsg), tolower(sp)))
utils::write.csv(res, paste0(stem, ".csv"), row.names = FALSE, na = "")
git_sha <- function(dir) {
  system2("git", c("-C", dir, "describe", "--always", "--dirty"), stdout = TRUE)
}
writeLines(c(
  sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
  sprintf("fresh: %s @ %s", utils::packageVersion("fresh"), git_sha(".")),
  sprintf("link rules: %s @ %s", rules_path, git_sha("~/Projects/repo/link")),
  sprintf("db: %s", q("SELECT current_database() || ':' || inet_server_port()")[[1]]),
  sprintf("source: %s + fresh_default.streams, %s rows", hab_src, n),
  sprintf("predicates: lake_rear = %s", gsub("\\s+", " ", preds$lake_rear)),
  sprintf("            wetland_rear = %s", gsub("\\s+", " ", preds$wetland_rear))),
  paste0(stem, ".txt"))
DBI::dbDisconnect(conn)
