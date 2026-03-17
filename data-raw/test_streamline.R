# Generate a small test AOI for fast integration tests
#
# Run interactively with a live DB connection. Output saved to inst/extdata/
# for use in integration tests without long query times.
#
# Uses a single steep tributary (BLK 360808793) in Bulkley watershed:
# 15 segments, 6.5km, max gradient 21%. fwa_slopealonginterval runs once.

library(fresh)
library(sf)

conn <- frs_db_conn()

# Grab the stream itself as the AOI — ST_Intersects matches exactly this BLK
aoi <- frs_db_query(conn,
  "SELECT ST_Union(geom) AS geom
   FROM whse_basemapping.fwa_stream_networks_sp
   WHERE blue_line_key = 360808793")

saveRDS(aoi, "inst/extdata/test_streamline.rds")
message("Saved test_streamline.rds")

# Verify
streams <- frs_db_query(conn, sprintf(
  "SELECT linear_feature_id, blue_line_key, gradient, geom
   FROM whse_basemapping.fwa_stream_networks_sp
   WHERE ST_Intersects(geom, ST_GeomFromText('%s', 3005))",
  st_as_text(st_union(st_geometry(aoi)))
))
message("Segments: ", nrow(streams), ", BLKs: ",
        length(unique(streams$blue_line_key)),
        ", max gradient: ", round(max(streams$gradient, na.rm = TRUE), 4))

DBI::dbDisconnect(conn)
