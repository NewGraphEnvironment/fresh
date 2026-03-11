# Generate bundled example data for the Byman-Ailport subbasin
#
# Run interactively with a live DB connection. Output saved to inst/extdata/
# for use in examples and tests without requiring a database.
#
# Area: Neexdzii Kwa (Upper Bulkley River), Byman Creek to Ailport Creek

library(fresh)
library(sf)

sf_use_s2(FALSE)

blk <- 360873822
drm_byman <- 208877
drm_ailport <- 233564

# --- AOI: subbasin polygon ---
aoi <- frs_watershed_at_measure(blk, drm_byman, upstream_measure = drm_ailport)

# --- Network features between the two points ---
result <- frs_network(blk, drm_byman, upstream_measure = drm_ailport,
  tables = list(
    streams = "whse_basemapping.fwa_stream_networks_sp",
    co = list(
      table = "bcfishpass.streams_co_vw",
      cols = c("segmented_stream_id", "blue_line_key", "gnis_name",
               "stream_order", "mapping_code", "rearing", "spawning",
               "access", "geom"),
      wscode_col = "wscode",
      localcode_col = "localcode"
    ),
    lakes = "whse_basemapping.fwa_lakes_poly"
  )
)

# --- Roads, FSRs, railway clipped to AOI ---
bb <- st_bbox(aoi)
env <- sprintf(
  "ST_MakeEnvelope(%s, %s, %s, %s, 3005)",
  bb["xmin"], bb["ymin"], bb["xmax"], bb["ymax"]
)

roads <- frs_db_query(sprintf(
  "SELECT transport_line_type_code, geom
   FROM whse_basemapping.transport_line
   WHERE transport_line_type_code IN
     ('RF','RH1','RH2','RA','RA1','RA2','RC1','RC2','RLO')
   AND ST_Intersects(geom, %s)", env
))
roads <- st_collection_extract(st_intersection(roads, aoi), "LINESTRING")
highways <- roads[roads$transport_line_type_code %in% c("RF", "RH1", "RH2"), ]
roads_other <- roads[!roads$transport_line_type_code %in% c("RF", "RH1", "RH2"), ]

fsr <- frs_db_query(sprintf(
  "SELECT road_section_name, geom
   FROM whse_forest_tenure.ften_road_section_lines_svw
   WHERE life_cycle_status_code = 'ACTIVE'
   AND file_type_description = 'Forest Service Road'
   AND ST_Intersects(geom, %s)", env
))
fsr <- st_collection_extract(st_intersection(fsr, aoi), "LINESTRING")

railway <- frs_db_query(sprintf(
  "SELECT track_name, geom
   FROM whse_basemapping.gba_railway_tracks_sp
   WHERE ST_Intersects(geom, %s)", env
))
if (nrow(railway) > 0) {
  railway <- st_collection_extract(st_intersection(railway, aoi), "LINESTRING")
}

# --- Save ---
saveRDS(
  list(
    aoi = aoi,
    streams = result$streams,
    co = result$co,
    lakes = result$lakes,
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
subbasins <- frs_watershed_split(pts, aoi = aoi)
saveRDS(subbasins, "inst/extdata/byman_ailport_subbasins.rds")

# Without AOI: full upstream watersheds, pairwise subtracted
subbasins_no_aoi <- frs_watershed_split(pts)
saveRDS(subbasins_no_aoi, "inst/extdata/byman_ailport_subbasins_no_aoi.rds")

# --- Summary ---
cat("Saved inst/extdata/byman_ailport.rds\n")
cat("Saved inst/extdata/byman_ailport_aoi.gpkg\n")
cat("Saved inst/extdata/byman_ailport_subbasins.rds\n")
cat("Saved inst/extdata/byman_ailport_subbasins_no_aoi.rds\n")
cat("Streams:", nrow(result$streams), "\n")
cat("Coho:", nrow(result$co), "\n")
cat("Lakes:", nrow(result$lakes), "\n")
cat("Roads:", nrow(roads_other), "\n")
cat("Highways:", nrow(highways), "\n")
cat("FSR:", nrow(fsr), "\n")
cat("Railway:", nrow(railway), "\n")
cat("Sub-basins (with AOI):", nrow(subbasins), "\n")
cat("Sub-basins (no AOI):", nrow(subbasins_no_aoi), "\n")
