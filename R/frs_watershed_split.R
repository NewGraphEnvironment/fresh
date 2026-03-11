#' Split a Watershed into Sub-Basins at Break Points
#'
#' Snaps break points to the nearest stream, delineates a watershed at each,
#' and performs pairwise subtraction to produce non-overlapping sub-basin
#' polygons. The most downstream (largest) watershed is first; each subsequent
#' sub-basin is the difference between its full watershed and all smaller
#' (upstream) watersheds.
#'
#' Stable identifiers come from `blk` (blue line key) and `drm` (downstream
#' route measure) — these never change regardless of how many points are in the
#' set. Extra columns from the input are preserved in the output.
#'
#' @param points A data frame (or sf) with `lon` and `lat` columns (WGS84).
#'   All extra columns (e.g. `name_basin`) are preserved in the output,
#'   making this the place to attach labels, site IDs, or any metadata to
#'   the resulting sub-basins.
#' @param aoi An `sf` or `sfc` polygon to clip results to. Optional. When
#'   provided, sub-basins are clipped to the AOI boundary. Include the AOI's
#'   downstream point as a break point to get complete tiling with no gaps
#'   (see Examples).
#' @param tolerance Numeric. Maximum snap distance in metres. Default `5000`.
#' @param ... Additional arguments passed to [frs_db_conn()].
#'
#' @return An `sf` data frame with columns: `blk`, `drm`, `gnis_name`,
#'   `area_km2`, any extra columns from the input, and `geometry`.
#'   Rows are ordered largest (most downstream) to smallest (most upstream).
#'
#' @details
#' Watersheds are sorted by area (descending), and each has all smaller
#' intersecting watersheds subtracted. This produces non-overlapping sub-basin
#' polygons that tile the study area.
#'
#' Points that fail to snap (no stream within `tolerance`) are dropped with a
#' message. If all points fail, an error is raised.
#'
#' @family watershed
#'
#' @export
#'
#' @examples
#' # Load cached data (Byman-Ailport subbasin, Neexdzii Kwa / Upper Bulkley)
#' d <- readRDS(system.file("extdata", "byman_ailport.rds", package = "fresh"))
#'
#' # With AOI: sub-basins clipped to study area boundary
#' subbasins <- readRDS(system.file("extdata", "byman_ailport_subbasins.rds",
#'   package = "fresh"))
#' cols <- sf::sf.colors(nrow(subbasins))
#' plot(sf::st_geometry(subbasins), col = cols, border = "grey40",
#'   main = "With AOI: clipped to study area")
#' plot(sf::st_geometry(d$aoi), border = "red", lwd = 2, add = TRUE)
#' text(sf::st_coordinates(sf::st_centroid(subbasins)),
#'   labels = subbasins$name_basin, cex = 0.7, font = 2)
#'
#' # Without AOI: full upstream watersheds, pairwise subtracted
#' subbasins_no_aoi <- readRDS(system.file("extdata",
#'   "byman_ailport_subbasins_no_aoi.rds", package = "fresh"))
#' cols2 <- sf::sf.colors(nrow(subbasins_no_aoi))
#' plot(sf::st_geometry(subbasins_no_aoi), col = cols2, border = "grey40",
#'   main = "Without AOI: full upstream watersheds")
#' text(sf::st_coordinates(sf::st_centroid(subbasins_no_aoi)),
#'   labels = subbasins_no_aoi$name_basin, cex = 0.7, font = 2)
#'
#' \dontrun{
#' # Live: split a watershed from a CSV of break points
#' pts <- read.csv(system.file("extdata", "break_points.csv", package = "fresh"))
#'
#' # Without AOI — full upstream watersheds, pairwise subtracted
#' subbasins <- frs_watershed_split(pts)
#'
#' # With AOI — clipped to study area. Include the downstream boundary
#' # point in break_points.csv for complete tiling with no gaps.
#' aoi <- frs_watershed_at_measure(360873822, 208877, upstream_measure = 233564)
#' subbasins <- frs_watershed_split(pts, aoi = aoi)
#' }
frs_watershed_split <- function(
    points,
    aoi = NULL,
    tolerance = 5000,
    ...
) {
  if (!is.data.frame(points)) stop("points must be a data frame", call. = FALSE)
  if (!all(c("lon", "lat") %in% names(points))) {
    stop("points must have 'lon' and 'lat' columns", call. = FALSE)
  }
  if (nrow(points) == 0L) stop("points has no rows", call. = FALSE)
  if (!is.null(aoi) && !inherits(aoi, c("sf", "sfc"))) {
    stop("aoi must be an sf or sfc object", call. = FALSE)
  }

  # Drop sf geometry if present — we snap from lon/lat
  if (inherits(points, "sf")) points <- sf::st_drop_geometry(points)

  # Identify extra columns
  snap_cols <- c("lon", "lat")
  extra_cols <- setdiff(names(points), snap_cols)

  # --- 1. Snap each point ---
  snapped <- list()
  for (i in seq_len(nrow(points))) {
    row <- tryCatch(
      frs_point_snap(
        x = points$lon[i],
        y = points$lat[i],
        tolerance = tolerance,
        ...
      ),
      error = function(e) NULL
    )
    if (is.null(row) || nrow(row) == 0L) {
      message(sprintf("Point %d (%.4f, %.4f) failed to snap - skipping",
                       i, points$lon[i], points$lat[i]))
      next
    }
    snapped[[length(snapped) + 1L]] <- data.frame(
      idx = i,
      blk = as.integer(row$blue_line_key[1]),
      drm = row$downstream_route_measure[1],
      gnis_name = if ("gnis_name" %in% names(row)) {
        nm <- row$gnis_name[1]
        if (is.null(nm) || is.na(nm)) "" else nm
      } else "",
      stringsAsFactors = FALSE
    )
  }

  if (length(snapped) == 0L) {
    stop("No points could be snapped to streams", call. = FALSE)
  }

  snapped_df <- do.call(rbind, snapped)

  # --- 2. Delineate watershed at each snap location ---
  watersheds <- vector("list", nrow(snapped_df))
  for (j in seq_len(nrow(snapped_df))) {
    ws <- tryCatch(
      frs_watershed_at_measure(
        snapped_df$blk[j],
        snapped_df$drm[j],
        ...
      ),
      error = function(e) {
        message(sprintf("Watershed failed for point %d (blk=%d, drm=%.0f): %s",
                         snapped_df$idx[j], snapped_df$blk[j],
                         snapped_df$drm[j], e$message))
        NULL
      }
    )
    if (!is.null(ws) && nrow(ws) > 0L) {
      watersheds[[j]] <- sf::st_transform(ws, 4326)
    }
  }

  valid <- which(vapply(watersheds, function(w) !is.null(w), logical(1)))
  if (length(valid) == 0L) {
    stop("No watersheds could be delineated", call. = FALSE)
  }

  snapped_valid <- snapped_df[valid, , drop = FALSE]
  ws_valid <- watersheds[valid]

  # --- 3. Sort by area (largest = most downstream) ---
  areas <- vapply(ws_valid, function(w) {
    as.numeric(sf::st_area(sf::st_transform(w, 3005)))
  }, numeric(1))

  ord <- order(-areas)
  snapped_valid <- snapped_valid[ord, , drop = FALSE]
  ws_valid <- ws_valid[ord]

  # --- 4. Pairwise subtraction ---
  sf::sf_use_s2(FALSE)
  n <- nrow(snapped_valid)
  subbasin_list <- vector("list", n)

  for (i in seq_len(n)) {
    poly <- ws_valid[[i]]

    # Subtract all smaller (upstream) watersheds that intersect
    if (i < n) {
      for (j in (i + 1L):n) {
        upstream <- ws_valid[[j]]
        if (!sf::st_intersects(poly, upstream, sparse = FALSE)[1, 1]) next

        poly <- tryCatch({
          d <- sf::st_difference(poly, upstream)
          d_types <- as.character(sf::st_geometry_type(d))
          if (any(d_types == "GEOMETRYCOLLECTION")) {
            d <- sf::st_collection_extract(d, "POLYGON")
          }
          if (nrow(d) > 0L) {
            sf::st_sf(geometry = sf::st_union(d))
          } else {
            poly
          }
        }, error = function(e) poly)
      }
    }

    # Build output row
    row_idx <- snapped_valid$idx[i]
    row_data <- data.frame(
      blk = snapped_valid$blk[i],
      drm = snapped_valid$drm[i],
      gnis_name = snapped_valid$gnis_name[i],
      stringsAsFactors = FALSE
    )

    # Append extra columns from original input
    if (length(extra_cols) > 0L) {
      for (col in extra_cols) {
        row_data[[col]] <- points[[col]][row_idx]
      }
    }

    subbasin_list[[i]] <- sf::st_sf(
      row_data,
      geometry = sf::st_geometry(poly)
    )
  }

  result <- do.call(rbind, subbasin_list)
  sf::st_crs(result) <- 4326
  result <- sf::st_cast(result, "MULTIPOLYGON")

  # Area in km2
  result$area_km2 <- round(
    as.numeric(sf::st_area(sf::st_transform(result, 3005))) / 1e6, 1
  )

  # --- 5. Optional clip ---
  if (!is.null(aoi)) {
    result <- frs_clip(result, aoi)
  }

  result
}
