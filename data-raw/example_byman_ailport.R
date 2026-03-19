# Generate bundled example data for the Byman-Ailport subbasin
#
# Run interactively with a live DB connection. Output saved to inst/extdata/
# for use in examples and tests without requiring a database.
#
# Area: Neexdzii Kwa (Upper Bulkley River), Byman Creek to Ailport Creek

devtools::load_all()
library(sf)

sf_use_s2(FALSE)

conn <- frs_db_conn()

blk <- 360873822
drm_byman <- 208877
drm_ailport <- 233564

# --- AOI: subbasin polygon ---
aoi <- frs_watershed_at_measure(conn, blk, drm_byman, upstream_measure = drm_ailport)

# --- Streams: extract to DB, enrich, read back ---
conn |>
  frs_network(blk, drm_byman, upstream_measure = drm_ailport,
    to = "working.byman_example") |>
  frs_col_join("working.byman_example",
    from = "fwa_stream_networks_channel_width",
    cols = c("channel_width", "channel_width_source"),
    by = "linear_feature_id")

streams <- frs_db_query(conn, "SELECT * FROM working.byman_example")

# --- Coho habitat from bcfishpass (for vignette comparison) ---
co <- frs_network(conn, blk, drm_byman, upstream_measure = drm_ailport,
  tables = list(
    co = list(
      table = "bcfishpass.streams_co_vw",
      cols = c("segmented_stream_id", "blue_line_key", "gnis_name",
               "stream_order", "mapping_code", "rearing", "spawning",
               "access", "geom"),
      wscode_col = "wscode",
      localcode_col = "localcode"
    )
  )
)

# --- Lakes ---
lakes <- frs_network(conn, blk, drm_byman, upstream_measure = drm_ailport,
  tables = list(lakes = "whse_basemapping.fwa_lakes_poly")
)

# --- Roads, FSRs, railway clipped to AOI ---
bb <- st_bbox(aoi)
env <- sprintf(
  "ST_MakeEnvelope(%s, %s, %s, %s, 3005)",
  bb["xmin"], bb["ymin"], bb["xmax"], bb["ymax"]
)

roads <- frs_db_query(conn, sprintf(
  "SELECT transport_line_type_code, geom
   FROM whse_basemapping.transport_line
   WHERE transport_line_type_code IN
     ('RF','RH1','RH2','RA','RA1','RA2','RC1','RC2','RLO')
   AND ST_Intersects(geom, %s)", env
))
roads <- st_collection_extract(st_intersection(roads, aoi), "LINESTRING")
highways <- roads[roads$transport_line_type_code %in% c("RF", "RH1", "RH2"), ]
roads_other <- roads[!roads$transport_line_type_code %in% c("RF", "RH1", "RH2"), ]

fsr <- frs_db_query(conn, sprintf(
  "SELECT road_section_name, geom
   FROM whse_forest_tenure.ften_road_section_lines_svw
   WHERE life_cycle_status_code = 'ACTIVE'
   AND file_type_description = 'Forest Service Road'
   AND ST_Intersects(geom, %s)", env
))
fsr <- st_collection_extract(st_intersection(fsr, aoi), "LINESTRING")

railway <- frs_db_query(conn, sprintf(
  "SELECT track_name, geom
   FROM whse_basemapping.gba_railway_tracks_sp
   WHERE ST_Intersects(geom, %s)", env
))
if (nrow(railway) > 0) {
  railway <- st_collection_extract(st_intersection(railway, aoi), "LINESTRING")
}

# --- Clean up working tables ---
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.byman_example")

# --- Save ---
saveRDS(
  list(
    aoi = aoi,
    streams = streams,
    co = co,
    lakes = lakes,
    roads = roads_other,
    highways = highways,
    fsr = fsr,
    railway = railway
  ),
  "inst/extdata/byman_ailport.rds"
)

# --- AOI as gpkg for loading into breaks app ---
st_write(aoi, "inst/extdata/byman_ailport_aoi.gpkg", delete_dsn = TRUE,
         quiet = TRUE)

# --- Sub-basins from break points ---
pts <- read.csv("inst/extdata/break_points.csv")

# With AOI: sub-basins clipped to study area boundary
subbasins <- frs_watershed_split(conn, pts, aoi = aoi)
saveRDS(subbasins, "inst/extdata/byman_ailport_subbasins.rds")

# Without AOI: full upstream watersheds, pairwise subtracted
subbasins_no_aoi <- frs_watershed_split(conn, pts)
saveRDS(subbasins_no_aoi, "inst/extdata/byman_ailport_subbasins_no_aoi.rds")

DBI::dbDisconnect(conn)

# --- Summary ---
cat("Saved inst/extdata/byman_ailport.rds\n")
cat("Saved inst/extdata/byman_ailport_aoi.gpkg\n")
cat("Saved inst/extdata/byman_ailport_subbasins.rds\n")
cat("Saved inst/extdata/byman_ailport_subbasins_no_aoi.rds\n")
cat("Streams:", nrow(streams), "\n")
cat("  with channel_width:", sum(!is.na(streams$channel_width)), "\n")
cat("Coho:", nrow(co), "\n")
cat("Lakes:", nrow(lakes), "\n")
cat("Roads:", nrow(roads_other), "\n")
cat("Highways:", nrow(highways), "\n")
cat("FSR:", nrow(fsr), "\n")
cat("Railway:", nrow(railway), "\n")
cat("Sub-basins (with AOI):", nrow(subbasins), "\n")
cat("Sub-basins (no AOI):", nrow(subbasins_no_aoi), "\n")
