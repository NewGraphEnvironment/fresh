# Parity check for fresh#247: the bulk frs_point_snap() against link's
# lnk_points_snap() on the PSCIS assessments link snaps today.
#
# Takes the PSCIS points inside one watershed group (or ALL of them) and
# snaps them with both functions at the same tolerance:
#   nf1 - num_features = 1: per stream_crossing_id, do both pick the same
#         blue_line_key and downstream_route_measure?
#   nf5 - num_features = 5: per stream_crossing_id, do both return the
#         same candidate segments, with the same measure on each?
# Known, intended difference: fresh excludes every placeholder segment
# (wscode_ltree <@ '999'), link only the exact code '999'. Crossings
# where link picked (nf1) or listed (nf5) a 999.* segment are counted
# separately and left out of the agreement figures. link also has no
# tie-break, so equidistant candidates (a point nearest a confluence)
# can come out in either order there; those are counted too.
#
# Needs link installed and whse_fish.pscis_assessment_svw loaded.
#
# Usage (from the fresh repo root):
#   Rscript data-raw/point_snap_parity_check.R [WSG] [TOLERANCE]
#   Rscript data-raw/point_snap_parity_check.R BULK 150
#   Rscript data-raw/point_snap_parity_check.R ALL 150
# Writes data-raw/logs/point_snap_parity_247/<wsg>_nf1.csv (every
# snapped crossing that is not identical), <wsg>_summary.csv and a .txt
# stamp. The nf1 categories partition every PSCIS crossing; "neither" is
# one neither function snapped within tolerance.

pkgload::load_all(".", quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
wsg <- if (length(args) >= 1) toupper(args[1]) else "BULK"
tolerance <- if (length(args) >= 2) as.numeric(args[2]) else 150
stopifnot(grepl("^[A-Z]{3,4}$", wsg), !is.na(tolerance), tolerance > 0)
if (!requireNamespace("link", quietly = TRUE)) {
  stop("link is not installed", call. = FALSE)
}
lnk_points_snap <- getExportedValue("link", "lnk_points_snap")

conn <- frs_db_conn()

tbl_pts <- "working.parity_247_pscis"
tbls <- c(tbl_pts, paste0("working.parity_247_",
                          c("link_nf1", "link_nf5", "fresh_nf1",
                            "fresh_nf5")))
drop_all <- function() for (t in tbls) .frs_test_drop(conn, t)
# on.exit() does not fire at a script's top level under Rscript; the work
# tables are dropped at the end, and here in case a run failed midway
drop_all()

# ALL = every PSCIS crossing in the province
wsg_filter <- if (wsg == "ALL") "" else sprintf(paste(
  "JOIN whse_basemapping.fwa_watershed_groups_poly w",
  "  ON ST_Intersects(p.geom, w.geom)",
  "WHERE w.watershed_group_code = %s"), DBI::dbQuoteString(conn, wsg))
invisible(DBI::dbExecute(conn, sprintf(paste(
  "CREATE TABLE %s AS",
  "SELECT p.stream_crossing_id, p.geom",
  "FROM whse_fish.pscis_assessment_svw p",
  "%s"), tbl_pts, wsg_filter)))
n_pts <- as.integer(DBI::dbGetQuery(
  conn, sprintf("SELECT count(*) AS n FROM %s", tbl_pts))$n)
message(sprintf("%s: %d PSCIS crossings, tolerance %g m", wsg, n_pts,
                tolerance))

timing <- list()
for (nf in c(1L, 5L)) {
  t0 <- Sys.time()
  lnk_points_snap(conn, table_in = tbl_pts,
                  table_out = sprintf("working.parity_247_link_nf%d", nf),
                  snap_tolerance = tolerance, num_features = nf)
  t_link <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  t0 <- Sys.time()
  frs_point_snap(conn, tbl_pts, col_id = "stream_crossing_id",
                 tolerance = tolerance, num_features = nf,
                 to = sprintf("working.parity_247_fresh_nf%d", nf))
  t_fresh <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  timing[[sprintf("nf%d", nf)]] <- c(link = t_link, fresh = t_fresh)
  message(sprintf("nf%d: link %.1f s, fresh %.1f s", nf, t_link, t_fresh))
}

# -- nf1: one pick per crossing ------------------------------------------------
nf1 <- DBI::dbGetQuery(conn, paste(
  "SELECT p.stream_crossing_id,",
  "  l.snapped_blue_line_key AS blk_link, f.blue_line_key AS blk_fresh,",
  "  l.downstream_route_measure AS drm_link,",
  "  f.downstream_route_measure AS drm_fresh,",
  "  l.distance_to_stream AS dist_link, f.distance_to_stream AS dist_fresh,",
  "  l.wscode_ltree <@ '999'::ltree AS link_999,",
  "  f.watershed_group_code AS wsg_fresh",
  # From the points table, so a crossing neither function snapped is a row
  sprintf("FROM %s p", tbl_pts),
  "LEFT JOIN working.parity_247_link_nf1 l",
  "  ON l.stream_crossing_id = p.stream_crossing_id",
  "LEFT JOIN working.parity_247_fresh_nf1 f",
  "  ON f.stream_crossing_id = p.stream_crossing_id"))
nf1$status <- with(nf1, ifelse(
  is.na(blk_link) & is.na(blk_fresh), "neither",
  ifelse(!is.na(link_999) & link_999, "link_999",
  ifelse(is.na(blk_fresh), "link_only",
  ifelse(is.na(blk_link), "fresh_only",
  ifelse(blk_link == blk_fresh & drm_link == drm_fresh, "same",
  ifelse(abs(dist_link - dist_fresh) < 1e-6, "tie", "differ")))))))

# -- nf5: candidate sets per crossing ------------------------------------------
# same_set: both sides list the same segments. tie_set: both sides hit the
# num_features limit and every segment only one side lists sits at the
# shared cut-off distance (the 5th candidate), where link has no tie-break
# and fresh breaks on linear_feature_id. drm_same: every segment both sides
# list carries the same measure, whether or not the sets match (all
# crossings, 999 ones included).
nf5 <- DBI::dbGetQuery(conn, paste(
  "WITH l AS (",
  "  SELECT stream_crossing_id, linear_feature_id, downstream_route_measure,",
  "    distance_to_stream, wscode_ltree <@ '999'::ltree AS is_999",
  "  FROM working.parity_247_link_nf5),",
  "f AS (",
  "  SELECT stream_crossing_id, linear_feature_id, downstream_route_measure,",
  "    distance_to_stream",
  "  FROM working.parity_247_fresh_nf5),",
  "side AS (",
  "  SELECT coalesce(lc.stream_crossing_id, fc.stream_crossing_id) AS id,",
  "    coalesce(lc.n, 0) AS n_link, coalesce(fc.n, 0) AS n_fresh,",
  "    lc.d_max AS d_link, fc.d_max AS d_fresh, coalesce(lc.any_999, FALSE)",
  "      AS link_999",
  "  FROM (SELECT stream_crossing_id, count(*) AS n,",
  "          max(distance_to_stream) AS d_max, bool_or(is_999) AS any_999",
  "        FROM l GROUP BY 1) lc",
  "  FULL JOIN (SELECT stream_crossing_id, count(*) AS n,",
  "               max(distance_to_stream) AS d_max",
  "             FROM f GROUP BY 1) fc",
  "    ON fc.stream_crossing_id = lc.stream_crossing_id),",
  "pairs AS (",
  "  SELECT coalesce(l.stream_crossing_id, f.stream_crossing_id) AS id,",
  "    l.linear_feature_id IS NOT NULL AND f.linear_feature_id IS NOT NULL",
  "      AS in_both,",
  "    coalesce(l.distance_to_stream, f.distance_to_stream) AS dist,",
  "    l.downstream_route_measure = f.downstream_route_measure AS drm_same",
  "  FROM l FULL JOIN f",
  "    ON f.stream_crossing_id = l.stream_crossing_id",
  "   AND f.linear_feature_id = l.linear_feature_id)",
  "SELECT p.id AS stream_crossing_id, s.link_999, s.n_link, s.n_fresh,",
  "  bool_and(p.in_both) AS same_set,",
  sprintf(paste(
    "  s.n_link = %1$d AND s.n_fresh = %1$d",
    "    AND abs(s.d_link - s.d_fresh) < 1e-6",
    "    AND bool_and(p.in_both OR abs(p.dist - s.d_fresh) < 1e-6) AS tie_set,"),
    5L),
  "  bool_and(coalesce(p.drm_same, TRUE)) AS drm_same",
  "FROM pairs p JOIN side s ON s.id = p.id",
  "GROUP BY p.id, s.link_999, s.n_link, s.n_fresh, s.d_link, s.d_fresh"))

summary <- data.frame(
  wsg = wsg,
  tolerance = tolerance,
  n_pscis = n_pts,
  nf1_same = sum(nf1$status == "same"),
  nf1_tie = sum(nf1$status == "tie"),
  nf1_differ = sum(nf1$status == "differ"),
  nf1_link_999 = sum(nf1$status == "link_999"),
  nf1_link_only = sum(nf1$status == "link_only"),
  nf1_fresh_only = sum(nf1$status == "fresh_only"),
  nf1_neither = sum(nf1$status == "neither"),
  nf1_fresh_wsg_na = sum(!is.na(nf1$blk_fresh) & is.na(nf1$wsg_fresh)),
  nf5_crossings = nrow(nf5),
  # Counted from the points table (nf1 has one row per crossing)
  nf5_neither = sum(!nf1$stream_crossing_id %in% nf5$stream_crossing_id),
  nf5_link_999 = sum(nf5$link_999),
  nf5_same_set = sum(!nf5$link_999 & nf5$same_set),
  nf5_tie_set = sum(!nf5$link_999 & !nf5$same_set & nf5$tie_set),
  nf5_differ_set = sum(!nf5$link_999 & !nf5$same_set & !nf5$tie_set),
  nf5_drm_mismatch = sum(!nf5$drm_same),
  secs_nf1_link = round(timing$nf1[["link"]], 1),
  secs_nf1_fresh = round(timing$nf1[["fresh"]], 1),
  secs_nf5_link = round(timing$nf5[["link"]], 1),
  secs_nf5_fresh = round(timing$nf5[["fresh"]], 1)
)
print(t(summary))

# Each set of categories must account for every crossing exactly once
cols_nf1 <- c("nf1_same", "nf1_tie", "nf1_differ", "nf1_link_999",
              "nf1_link_only", "nf1_fresh_only", "nf1_neither")
cols_nf5 <- c("nf5_neither", "nf5_link_999", "nf5_same_set", "nf5_tie_set",
              "nf5_differ_set")
stopifnot(
  nrow(nf1) == n_pts,
  sum(unlist(summary[cols_nf1])) == n_pts,
  sum(unlist(summary[cols_nf5])) == n_pts
)

dir_out <- file.path("data-raw", "logs", "point_snap_parity_247")
dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(nf1[!nf1$status %in% c("same", "neither"), ],
                 file.path(dir_out, paste0(wsg, "_nf1.csv")),
                 row.names = FALSE)
utils::write.csv(summary, file.path(dir_out, paste0(wsg, "_summary.csv")),
                 row.names = FALSE)
writeLines(c(
  sprintf("run: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  sprintf("fresh: %s (%s)", as.character(utils::packageVersion("fresh")),
          system("git rev-parse --short HEAD", intern = TRUE)),
  sprintf("link: %s", as.character(utils::packageVersion("link"))),
  sprintf("db: %s", DBI::dbGetQuery(conn, "SELECT current_database()")[[1]])
), file.path(dir_out, paste0(wsg, ".txt")))

drop_all()
DBI::dbDisconnect(conn)
