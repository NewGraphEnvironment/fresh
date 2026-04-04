# Fetch crossings from bcfishpass (remote DB via SSH tunnel)
#
# Source: bcfishpass.crossings — unified view combining PSCIS assessments,
#   modelled stream crossings, CABD dams, and misc barriers.
# Canonical repo: https://github.com/smnorris/bcfishpass
#
# Requires SSH tunnel on port 63333:
#   ssh -L 63333:localhost:5432 <remote>
#
# Crossings data updates when bcfishpass model is re-run. Re-run this script
# to sync. PSCIS source data comes from BC Data Catalogue; modelled crossings
# are computed by bcfishpass from road/stream intersections.

conn <- DBI::dbConnect(
  RPostgres::Postgres(),
  host = "localhost",
  port = 63333,
  dbname = "bcfishpass",
  user = "newgraph"
)

crossings <- DBI::dbGetQuery(conn,
  "SELECT aggregated_crossings_id,
          crossing_source,
          barrier_status,
          crossing_type_code,
          pscis_status,
          blue_line_key,
          downstream_route_measure,
          watershed_group_code,
          gnis_stream_name,
          stream_order
   FROM bcfishpass.crossings
   WHERE blue_line_key IS NOT NULL
     AND downstream_route_measure IS NOT NULL"
)

DBI::dbDisconnect(conn)

write.csv(crossings, "inst/extdata/crossings.csv", row.names = FALSE, na = "")

cat("Saved inst/extdata/crossings.csv\n")
cat("  Crossings:", nrow(crossings), "\n")
cat("  Sources:\n")
print(table(crossings$crossing_source))
cat("  Barrier status:\n")
print(table(crossings$barrier_status, useNA = "ifany"))
