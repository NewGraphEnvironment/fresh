# Generate cached data for the habitat pipeline vignette
#
# Runs the full coho habitat classification pipeline on the Byman-Ailport
# subbasin. Saves results to inst/extdata/byman_ailport_habitat.rds for
# the vignette to consume — no DB connection needed at render time.
#
# Run interactively with a live DB connection:
#   Rscript data-raw/vignette_habitat_pipeline.R
#
# The vignette loads this .rds and produces all plots and tables from it.
# Bookdown controls the full knit, so figure numbering and cross-references
# work.

devtools::load_all()
library(sf)

sf_use_s2(FALSE)

conn <- frs_db_conn()

# ==========================================================================
# Study area
# ==========================================================================
# Byman Creek to Ailport Creek on the Neexdzii Kwa (Upper Bulkley River)
# mainstem in the traditional territory of the Wet'suwet'en.
# blue_line_key identifies the stream, downstream_route_measure gives the
# position in metres from the mouth.
blk <- 360873822
drm_byman <- 208877    # downstream boundary (Byman Creek)
drm_ailport <- 233564  # upstream boundary (Ailport Creek)

# ==========================================================================
# Parameters
# ==========================================================================
# Habitat thresholds from bcfishpass defaults — spawning and rearing
# gradient, channel width, and MAD per species. Bundled CSV mirrors
# https://github.com/smnorris/bcfishpass/tree/main/parameters/example_newgraph
params_all <- frs_params(csv = system.file("extdata",
  "parameters_habitat_thresholds.csv", package = "fresh"))

# Coho thresholds:
#   spawn: gradient 0-5.49%, channel_width >= 2m, MAD 0.164-9999 m3/s
#   rear:  gradient 0-5.49%, channel_width >= 1.5m, MAD 0.03-40 m3/s
params_co <- params_all$CO

# Access gradient and spawn gradient min — fresh-specific additions.
# Access thresholds sourced from bcfishpass model_access_ch_cm_co_pk_sk.sql:16
# Spawn gradient min is our addition — bcfishpass defaults to 0.
params_fresh <- read.csv(system.file("extdata",
  "parameters_fresh.csv", package = "fresh"))

# Coho-specific fresh params:
#   access_gradient_max = 0.15 (15% — coho cannot pass)
#   spawn_gradient_min = 0.0025 (0.25% — salmonids don't spawn in flat water)
co_fresh <- params_fresh[params_fresh$species_code == "CO", ]

# Maximum spawn gradient from bcfishpass (5.49%)
spawn_gradient_max <- params_co$spawn_gradient_max

# Access gradient threshold (15% for coho)
access_gradient_max <- co_fresh$access_gradient_max

# Spawn channel width range from bcfishpass (2m to 9999m)
spawn_cw <- params_co$ranges$spawn$channel_width

# ==========================================================================
# Watershed polygon
# ==========================================================================
# Delineate the study area between the two points — network subtraction
# (upstream of Byman minus upstream of Ailport), no spatial clipping.
message("Delineating study area watershed...")
aoi <- frs_watershed_at_measure(conn, blk, drm_byman,
  upstream_measure = drm_ailport)

# ==========================================================================
# Step 1: Extract stream network and enrich
# ==========================================================================
# frs_network(to=) writes the FWA base stream network to a working table
# on PostgreSQL. Data stays on the DB — no R memory bottleneck.
# frs_col_join() adds channel width from the fwapg regression model.
# frs_col_generate() converts gradient to a PostgreSQL generated column
# so it auto-recomputes when geometry is split by breaks.
message("Extracting stream network to working table...")
conn |>
  frs_network(blk, drm_byman, upstream_measure = drm_ailport,
    to = "working.byman_habitat") |>
  frs_col_join("working.byman_habitat",
    from = "fwa_stream_networks_channel_width",
    cols = c("channel_width", "channel_width_source"),
    by = "linear_feature_id") |>
  frs_col_generate("working.byman_habitat")

# Snapshot of the network before any breaks (for edge type plot)
before <- frs_db_query(conn,
  "SELECT gradient, channel_width, edge_type, waterbody_key, geom
   FROM working.byman_habitat")

# ==========================================================================
# Step 2: Access barriers
# ==========================================================================
# Two sources of access barriers for coho:
#
# 1. Gradient barriers — 100m segments where gradient >= 15%.
#    frs_break_find() with attribute mode samples slope at each vertex
#    over 100m intervals using fwa_slopealonginterval().
#
# 2. Barrier falls — from bcfishpass falls table where barrier_ind = TRUE.
#    frs_break_find() with table mode pulls from an existing point table.
#    append = TRUE adds falls to the same breaks table as gradient barriers.
#    aoi scopes the query to our study area (not all of BC).
message("Finding access barriers (gradient >= ",
        access_gradient_max * 100, "% + barrier falls)...")

frs_break_find(conn, "working.byman_habitat",
  attribute = "gradient", threshold = access_gradient_max,
  to = "working.breaks_access")

frs_break_find(conn, "working.byman_habitat",
  points_table = "bcfishpass.falls_vw",
  where = "barrier_ind = TRUE", aoi = aoi,
  to = "working.breaks_access", append = TRUE)

# Split stream geometry at all access barrier locations
frs_break_apply(conn, "working.byman_habitat",
  breaks = "working.breaks_access")

# Label each segment as accessible or not — segments upstream of any
# access barrier (gradient or falls) are inaccessible to coho
conn |>
  frs_classify("working.byman_habitat", label = "accessible",
    breaks = "working.breaks_access")

# Access break points with geometry for plotting (locate on network
# using ST_LocateAlong — same approach as bcfishpass barriers_gradient.sql)
breaks_access_sf <- frs_db_query(conn,
  "SELECT b.blue_line_key, b.downstream_route_measure,
     ST_Force2D((ST_Dump(ST_LocateAlong(s.geom, b.downstream_route_measure))).geom)::geometry(Point, 3005) AS geom
   FROM working.breaks_access b
   JOIN whse_basemapping.fwa_stream_networks_sp s
     ON b.blue_line_key = s.blue_line_key
     AND b.downstream_route_measure >= s.downstream_route_measure
     AND b.downstream_route_measure < s.upstream_route_measure")

# ==========================================================================
# Step 3: Habitat classification
# ==========================================================================
# Break at the habitat gradient threshold (5.49%) — splits segments at
# gradient transitions so classification is precise.
message("Breaking at habitat gradient threshold (",
        spawn_gradient_max * 100, "%)...")
conn |>
  frs_break("working.byman_habitat",
    attribute = "gradient",
    threshold = spawn_gradient_max,
    to = "working.breaks_habitat")

# Classify habitat within accessible reaches only.
# Baseline spawning uses gradient 0-5.49% (bcfishpass default, no minimum).
# Rearing uses the same gradient range with wider channel width.
# Lake rearing applies channel width on lake-connected segments —
# recovering habitat that bcfishpass scores as rearing = 0 (bcfishpass#408).
message("Classifying habitat...")
conn |>
  frs_classify("working.byman_habitat", label = "co_spawning",
    ranges = list(gradient = c(0, spawn_gradient_max),
                  channel_width = spawn_cw),
    where = "accessible IS TRUE") |>
  frs_classify("working.byman_habitat", label = "co_rearing",
    ranges = params_co$ranges$rear[c("gradient", "channel_width")],
    where = "accessible IS TRUE") |>
  frs_classify("working.byman_habitat", label = "co_lake_rearing",
    ranges = list(channel_width = params_co$ranges$rear$channel_width),
    where = "accessible IS TRUE AND waterbody_key IN (SELECT waterbody_key FROM whse_basemapping.fwa_lakes_poly)")

# Collapse boolean labels into a single mapping code column.
# Priority order: spawning > rearing > lake rearing > accessible > inaccessible.
conn |>
  frs_categorize("working.byman_habitat",
    label = "habitat_type",
    cols = c("co_spawning", "co_rearing", "co_lake_rearing", "accessible"),
    values = c("CO_SPAWNING", "CO_REARING", "CO_LAKE_REARING", "ACCESSIBLE"),
    default = "INACCESSIBLE")

# Read the fully classified network
classified <- frs_db_query(conn,
  "SELECT linear_feature_id, blue_line_key, edge_type, gradient,
          channel_width, waterbody_key, accessible, co_spawning,
          co_rearing, co_lake_rearing, habitat_type, geom
   FROM working.byman_habitat")

# ==========================================================================
# Step 4: Waterbodies
# ==========================================================================
# Waterbodies on coho habitat — only those connected to accessible streams
# with rearing or lake rearing classification. Clipped to study area polygon
# so boundary-straddling waterbodies don't extend outside the AOI.
message("Reading waterbodies...")
waterbodies <- frs_network(conn, blk, drm_byman,
  upstream_measure = drm_ailport, clip = aoi,
  tables = list(
    lakes = list(table = "whse_basemapping.fwa_lakes_poly",
      from = "working.byman_habitat",
      extra_where = "co_rearing IS TRUE OR co_lake_rearing IS TRUE"),
    wetlands = list(table = "whse_basemapping.fwa_wetlands_poly",
      from = "working.byman_habitat",
      extra_where = "co_rearing IS TRUE")))

# All accessible waterbodies (background layer for mapping)
all_wb <- frs_network(conn, blk, drm_byman,
  upstream_measure = drm_ailport, clip = aoi,
  tables = list(
    lakes = list(table = "whse_basemapping.fwa_lakes_poly",
      from = "working.byman_habitat", extra_where = "accessible IS TRUE"),
    wetlands = list(table = "whse_basemapping.fwa_wetlands_poly",
      from = "working.byman_habitat", extra_where = "accessible IS TRUE")))

# ==========================================================================
# Step 5: Aggregate habitat upstream of crossings
# ==========================================================================
# Create a points table with crossings in the subbasin plus the subbasin
# outlet point to get total habitat lengths. frs_aggregate() traverses the
# network upstream from each point and sums classified habitat.
message("Aggregating habitat at crossings...")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.byman_crossings")
DBI::dbExecute(conn, sprintf(
  "CREATE TABLE working.byman_crossings AS
   SELECT aggregated_crossings_id AS id, blue_line_key, downstream_route_measure
   FROM bcfishpass.crossings
   WHERE blue_line_key = %s
     AND downstream_route_measure >= %s AND downstream_route_measure <= %s
   UNION ALL
   SELECT 'subbasin_total' AS id, %s AS blue_line_key, %s AS downstream_route_measure",
  blk, drm_byman, drm_ailport, blk, drm_byman))

crossings <- frs_db_query(conn,
  "SELECT aggregated_crossings_id, blue_line_key,
          downstream_route_measure, barrier_status, geom
   FROM bcfishpass.crossings
   WHERE blue_line_key = 360873822
     AND downstream_route_measure >= 208877 AND downstream_route_measure <= 233564")

agg <- frs_aggregate(conn,
  points = "working.byman_crossings",
  features = "working.byman_habitat",
  id_col = c("id", "blue_line_key", "downstream_route_measure"),
  metrics = c(
    total_km = "ROUND(SUM(ST_Length(f.geom))::numeric / 1000, 1)",
    accessible_km = "ROUND(SUM(CASE WHEN f.accessible IS TRUE THEN ST_Length(f.geom) ELSE 0 END)::numeric / 1000, 1)",
    spawning_km = "ROUND(SUM(CASE WHEN f.co_spawning IS TRUE THEN ST_Length(f.geom) ELSE 0 END)::numeric / 1000, 1)",
    rearing_km = "ROUND(SUM(CASE WHEN f.co_rearing IS TRUE THEN ST_Length(f.geom) ELSE 0 END)::numeric / 1000, 1)",
    lake_rearing_km = "ROUND(SUM(CASE WHEN f.co_lake_rearing IS TRUE THEN ST_Length(f.geom) ELSE 0 END)::numeric / 1000, 1)"),
  direction = "upstream")

# ==========================================================================
# Step 6: Spawning scenario comparison
# ==========================================================================
# The baseline uses spawn gradient min = 0% (bcfishpass default).
# We classify three additional scenarios with increasing minimum gradients
# to show the effect of excluding low-gradient reaches where salmonids
# are unlikely to spawn.
message("Classifying spawning scenarios...")
conn |>
  frs_classify("working.byman_habitat", label = "co_spawn_025",
    ranges = list(gradient = c(0.0025, spawn_gradient_max),
                  channel_width = c(spawn_cw[1], 9999)),
    where = "accessible IS TRUE") |>
  frs_classify("working.byman_habitat", label = "co_spawn_05",
    ranges = list(gradient = c(0.005, spawn_gradient_max),
                  channel_width = c(spawn_cw[1], 9999)),
    where = "accessible IS TRUE") |>
  frs_classify("working.byman_habitat", label = "co_spawn_075",
    ranges = list(gradient = c(0.0075, spawn_gradient_max),
                  channel_width = c(spawn_cw[1], 9999)),
    where = "accessible IS TRUE")

scenarios <- frs_db_query(conn,
  "SELECT co_spawning, co_spawn_025, co_spawn_05, co_spawn_075, geom
   FROM working.byman_habitat")

# ==========================================================================
# Falls for mapping
# ==========================================================================
falls <- frs_network(conn, blk, drm_byman, upstream_measure = drm_ailport,
  tables = list(falls = "bcfishpass.falls_vw"))

# ==========================================================================
# Clean up working tables
# ==========================================================================
for (tbl in c("working.byman_habitat", "working.breaks_access",
               "working.breaks_habitat", "working.byman_crossings")) {
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", tbl))
}
DBI::dbDisconnect(conn)

# ==========================================================================
# Save
# ==========================================================================
saveRDS(
  list(before = before, classified = classified,
       breaks_access_sf = breaks_access_sf,
       waterbodies = waterbodies, all_wb = all_wb, falls = falls,
       crossings = crossings, agg = agg, scenarios = scenarios, aoi = aoi),
  "inst/extdata/byman_ailport_habitat.rds")

message("Saved inst/extdata/byman_ailport_habitat.rds")
message("  Before: ", nrow(before), " segments")
message("  Classified: ", nrow(classified), " segments")
message("  Crossings: ", nrow(crossings))
message("  Falls: ", nrow(falls))
message("Done.")
