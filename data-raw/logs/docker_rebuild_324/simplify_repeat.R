# #306: does a simplified polygon repeat between calls on one database?
# On one connection, 20 times each:
#   sql    ST_SimplifyPreserveTopology(Tahtsa Reach, 100): points and md5 of the EWKB
#          (OFFSET 0 keeps the subquery from being inlined, which would
#          evaluate the simplify once for the count and again for the md5)
#   fetch  frs_lake_fetch(aoi = Tahtsa Reach buffered 10 m, simplify_m = 100):
#          rows and md5 of the whole layer's WKB (little endian)
# Run from the repo root against a local fwapg on <port>:
#   Rscript data-raw/logs/docker_rebuild_324/simplify_repeat.R 5433 > data-raw/logs/docker_rebuild_324/simplify_repeat_5433.txt
port <- commandArgs(TRUE)[1]
stopifnot(!is.na(port))
suppressPackageStartupMessages(devtools::load_all(quiet = TRUE))
conn <- frs_db_conn(host = "localhost", port = as.integer(port), dbname = "fwapg",
                    user = "postgres", password = "postgres")
on.exit(DBI::dbDisconnect(conn))

lake_id <- 700228651
cat(sprintf("# %s port %s: %s\n", format(Sys.time(), tz = "UTC", usetz = TRUE), port,
            DBI::dbGetQuery(conn, "SELECT postgis_full_version() AS v")$v))

sql <- sprintf(
  "SELECT ST_NPoints(s) AS n, md5(ST_AsEWKB(s)) AS h
   FROM (SELECT ST_SimplifyPreserveTopology(geom, 100) AS s
         FROM whse_basemapping.fwa_lakes_poly WHERE waterbody_poly_id = %d
         OFFSET 0) q",
  as.integer(lake_id))
s <- do.call(rbind, lapply(1:20, function(i) DBI::dbGetQuery(conn, sql)))
cat("\n## sql: points, md5 (first 12), calls\n")
print(aggregate(list(calls = s$n), list(points = s$n, md5 = substr(s$h, 1, 12)), length),
      row.names = FALSE)

aoi <- sf::st_read(conn, query = sprintf(
  "SELECT ST_Buffer(geom, 10) AS geom FROM whse_basemapping.fwa_lakes_poly
   WHERE waterbody_poly_id = %d", as.integer(lake_id)), quiet = TRUE)
f <- vapply(1:20, function(i) {
  x <- frs_lake_fetch(conn, aoi = aoi, simplify_m = 100)
  tf <- tempfile()
  writeBin(unlist(sf::st_as_binary(sf::st_geometry(x), endian = "little")), tf)
  paste(nrow(x), unname(tools::md5sum(tf)))
}, "")
cat("\n## frs_lake_fetch(aoi =, simplify_m = 100): rows and layer md5 (first 12), calls\n")
tab <- table(substr(f, 1, nchar(sub(" .*", "", f)) + 13))
print(data.frame(rows_md5 = names(tab), calls = as.integer(tab)), row.names = FALSE)
