# Fetch barrier falls from bcfishpass (remote DB via SSH tunnel)
#
# Source: bcfishpass.falls_vw (materialized from CABD waterfalls + FISS obstacles)
# Canonical repo: https://github.com/smnorris/bcfishpass
#
# Requires SSH tunnel on port 63333:
#   ssh -L 63333:localhost:5432 <remote>
#
# Falls data is stable — re-run when bcfishpass refreshes CABD data.

conn <- DBI::dbConnect(
  RPostgres::Postgres(),
  host = "localhost",
  port = 63333,
  dbname = "bcfishpass",
  user = "newgraph"
)

falls <- DBI::dbGetQuery(conn,
  "SELECT blue_line_key,
          downstream_route_measure,
          watershed_group_code,
          falls_name,
          height_m,
          barrier_ind
   FROM bcfishpass.falls_vw
   WHERE barrier_ind = TRUE"
)

DBI::dbDisconnect(conn)

write.csv(falls, "inst/extdata/falls.csv", row.names = FALSE)

cat("Saved inst/extdata/falls.csv\n")
cat("  Barrier falls:", nrow(falls), "\n")
cat("  Watershed groups:", length(unique(falls$watershed_group_code)), "\n")
