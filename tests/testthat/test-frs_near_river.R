# frs_near_river(): distance down to the nearest river (#259). Synthetic
# network in pg_temp (helper-near_river.R).

nr_run <- function(conn, q = 3, d = 1000, tbl = "pg_temp.nr_streams",
                   to = "pg_temp.nr_near", ...) {
  frs_near_river(conn, tbl, to, discharge_min = q, distance_max = d,
                 verbose = FALSE, ...)
}

test_that("bank distance leaves out the target polygon's connector", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn, d = 5000)
  # The connector's own row (10) sits inside polygon 7: distance 0.
  expect_identical(.nr_dist(conn),
                   c(`10` = 0, `11` = 0, `12` = 400, `13` = 900,
                     `14` = 1900, `15` = 2900))
  # The river's own rows (5 m3/s) are not measured.
  n_river <- DBI::dbGetQuery(conn, "SELECT count(*)::int n FROM pg_temp.nr_near
                                    WHERE id_segment IN (1, 2, 3)")$n
  expect_identical(n_river, 0L)
})

test_that("distance_max caps at the bank distance, inclusive", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Scale 0.01: the prefilter passes everything, so the network cap decides.
  .nr_fixture(conn, .nr_tributary(), scale = 0.01)
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  # 950 m: t3 is 900 m from the bank but 1000 m from the centreline.
  nr_run(conn, d = 950)
  expect_identical(names(.nr_dist(conn)), c("10", "11", "12", "13"))
  nr_run(conn, d = 1900)
  expect_true("14" %in% names(.nr_dist(conn)))
  nr_run(conn, d = 1899.9)
  expect_false("14" %in% names(.nr_dist(conn)))
})

test_that("the bank subtraction holds with the straight-line prefilter live", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # At scale 1 the prefilter radius is distance_max + the longest
  # connector, which must still reach t3's target 1000 m away.
  .nr_fixture(conn, .nr_tributary(), scale = 1)
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn, d = 950)
  expect_identical(.nr_dist(conn)[["13"]], 900)
})

test_that("a discharge above the river's finds nothing", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn, q = 10, d = 5000)
  expect_length(.nr_dist(conn, q = 10), 0)
})

test_that("NULL discharge is never a target", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  segs <- .nr_tributary()
  segs$mad[segs$id == 2] <- NA
  .nr_fixture(conn, segs)
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn, d = 5000)
  # t1 now reaches row 1, past 1000 m of NULL river: 1000 m from the bank.
  expect_identical(.nr_dist(conn)[["11"]], 1000)
  # NULL-discharge rows are measured: row 2 reaches row 1 at 0, row 15
  # reaches row 14 (0.2 m3/s) at 0. Row 2 itself serves no one.
  nr_run(conn, q = 0.1, d = 5000)
  d01 <- .nr_dist(conn, q = 0.1)
  expect_identical(names(d01), c("2", "15"))
})

test_that("two discharges in one call measure each from its own origins", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn, q = c(3, 0.1), d = c(1000, 500))
  expect_identical(.nr_dist(conn),
                   c(`10` = 0, `11` = 0, `12` = 400, `13` = 900))
  # At 0.1 only row 15 (NULL) is below the threshold; row 14 lies at 0.
  expect_identical(.nr_dist(conn, q = 0.1), c(`15` = 0))
})

test_that("one discharge at two distances is walked twice, each on its own", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn, q = c(3, 3), d = c(500, 1000))
  expect_identical(.nr_dist(conn, d = 500), c(`10` = 0, `11` = 0, `12` = 400))
  expect_identical(.nr_dist(conn, d = 1000),
                   c(`10` = 0, `11` = 0, `12` = 400, `13` = 900))
})

test_that("a polygon passed through keeps its connector in the distance", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_passthrough())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn, q = c(3, 0.5), d = c(5000, 5000))
  expect_identical(.nr_dist(conn)[["31"]], 550)
  expect_identical(.nr_dist(conn, q = 0.5)[["31"]], 0)
  # The small river's connector (20, 1 m3/s) is not a target at 0.5.
  expect_identical(.nr_dist(conn)[["21"]], 0)
})

test_that("a jump across a side-line connector into the polygon is the bank", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  local_mocked_bindings(.frs_near_river_polygons = function() "pg_temp.nr_polys")
  .nr_fixture(conn, .nr_sideline())
  # Polygon 7's bank runs along y = 100, where the tributary ends.
  .nr_polys(conn, list(list(wbk = 7, x0 = -10, y0 = -100, x1 = 2100, y1 = 100)))
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn, d = 5000)
  expect_equal(.nr_dist(conn), c(`41` = 0, `42` = 400), tolerance = 1e-9)
})

test_that("only the part of a jump inside the polygon is left out", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  local_mocked_bindings(.frs_near_river_polygons = function() "pg_temp.nr_polys")
  .nr_fixture(conn, .nr_sideline())
  # The bank is at y = 50: the tributary ends 50 m outside polygon 7 (on
  # a side channel the walk drops), so 50 m of the 100 m jump counts.
  .nr_polys(conn, list(list(wbk = 7, x0 = -10, y0 = -50, x1 = 2100, y1 = 50)))
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn, d = 5000)
  expect_equal(.nr_dist(conn), c(`41` = 50, `42` = 450), tolerance = 1e-9)
  # With no polygon for 7, the whole jump counts.
  DBI::dbExecute(conn, "DELETE FROM pg_temp.nr_polys")
  nr_run(conn, d = 5000)
  expect_equal(.nr_dist(conn), c(`41` = 100, `42` = 500), tolerance = 1e-9)
})

test_that("a tributary meeting its parent mid-row walks only the part below", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # Row 2 now carries 2 m3/s (not a target at 3). The tributary's mouth
  # sits 100 m off row 2's midpoint, so the walk jumps 100 m (polygon 7's
  # entry, left out) and walks 500 m of row 2 down to row 1.
  local_mocked_bindings(.frs_near_river_polygons = function() "pg_temp.nr_polys")
  segs <- .nr_sideline()
  segs$mad[segs$id == 2] <- 2
  .nr_fixture(conn, segs)
  .nr_polys(conn, list(list(wbk = 7, x0 = -10, y0 = -100, x1 = 2100, y1 = 100)))
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn, d = 5000)
  # Row 2 itself is now measured: row 1 lies right below it.
  expect_equal(.nr_dist(conn), c(`2` = 0, `41` = 500, `42` = 900),
               tolerance = 1e-9)
})

test_that("two entries into one polygon cannot make an answer depend on the call", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  local_mocked_bindings(.frs_near_river_polygons = function() "pg_temp.nr_polys")
  # The tributary jumps 100 m into polygon 7 onto row 2 (2 m3/s), and row
  # 2 jumps another 100 m onto row 1 (5 m3/s): 200 m of entries against a
  # 100 m allowance (the one side-line connector).
  segs <- .nr_sideline()
  segs$mad[segs$id == 2] <- 2
  segs$y[segs$id == 1] <- -100
  # Row 1 ends at x = 990, so the second jump is not exactly vertical:
  # GEOS 3.9.0 intersects an exactly vertical x = 1000 line with the box
  # as EMPTY (2026-10-21).
  segs$len[segs$id == 1] <- 990
  .nr_fixture(conn, segs)
  .nr_polys(conn, list(list(wbk = 7, x0 = -10, y0 = -150, x1 = 2100, y1 = 100)))
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn, q = 3, d = 550)
  alone <- .nr_dist(conn)
  nr_run(conn, q = c(3, 1), d = c(550, 9000))
  expect_identical(.nr_dist(conn), alone)
  # Tributary row 41: 100 + 500 + 100.5 m walked, 100 m left out, where
  # the two entries alone would leave out 200.
  nr_run(conn, q = 3, d = 5000)
  expect_equal(.nr_dist(conn)[["41"]], 100 + 500 + sqrt(100^2 + 10^2) - 100,
               tolerance = 1e-9)
})

test_that("a row the prefilter drops cuts the path behind it", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  # The tributary's mouth (0, 0) jumps 1,100 m to river row 61, wholly
  # beyond a 1,000 m reach, which runs on into row 60 (5 m3/s), back
  # within 200 m of the mouth. Through row 61 the river is 1,100 m away.
  segs <- rbind(
    .nr_seg(60, 1, "100", "100.400", 0, 900, 1250L, NA, 5,
            geom = "LINESTRING(0 200, 0 1100)"),
    .nr_seg(61, 1, "100", "100.400", 900, 500, 1250L, NA, 5,
            geom = "LINESTRING(0 1100, 500 1100)"),
    .nr_seg(62, 2, "100.500", drm = 0, len = 100, mad = 0.2,
            geom = "LINESTRING(0 0, -100 0)"))
  .nr_fixture(conn, segs)
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn, q = 3, d = 1000)
  expect_length(.nr_dist(conn), 0)
  nr_run(conn, q = c(3, 1), d = c(1000, 9000))
  expect_length(.nr_dist(conn), 0)
  nr_run(conn, q = 3, d = 5000)
  expect_equal(.nr_dist(conn)[["62"]], 1100, tolerance = 1e-9)
})

test_that("a stretch outside the table counts at its straight length", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_offtable())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn, d = 5000)
  expect_identical(.nr_dist(conn), c(`51` = 2000, `52` = 2500))
  # One discharge and distance gets one answer, whatever else is asked.
  nr_run(conn, q = c(3, 1), d = c(1000, 9000))
  expect_length(.nr_dist(conn), 0)
  nr_run(conn, q = 3, d = 1000)
  expect_length(.nr_dist(conn), 0)
})

test_that("bank = FALSE measures to the centreline", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.frs_near_river_walk")
  DBI::dbExecute(conn, .frs_near_river_walk_sql("pg_temp.nr_streams",
    "pg_temp.frs_near_river_walk", 3, 5000, conn_max = 100, entry_max = 0,
    bank = FALSE))
  d <- DBI::dbGetQuery(conn, "SELECT origin_id, dist_m
    FROM pg_temp.frs_near_river_walk WHERE discharge_min = 3
    ORDER BY origin_id")
  expect_identical(stats::setNames(d$dist_m, d$origin_id),
                   c(`10` = 0, `11` = 100, `12` = 500, `13` = 1000,
                     `14` = 2000, `15` = 3000))
})

test_that("on the origin's own line a row upstream is never on the path", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  segs <- .nr_tributary()
  # Row 15 (upstream of 13 and 14) carries a local code below theirs, so
  # FWA_Downstream()'s code branch calls it downstream of both.
  segs$lc[segs$id == 15] <- "100.499"
  .nr_fixture(conn, segs)
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn, d = 5000)
  expect_identical(.nr_dist(conn)[c("13", "14")], c(`13` = 900, `14` = 1900))
})

test_that("only the table's groups are replaced", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  nr_run(conn)
  DBI::dbExecute(conn, "INSERT INTO pg_temp.nr_near VALUES
                          (999, 'TEST', 3, 1000, 1), (999, 'OTHR', 3, 1000, 1)")
  nr_run(conn)
  kept <- DBI::dbGetQuery(conn, "SELECT watershed_group_code w
                                 FROM pg_temp.nr_near WHERE id_segment = 999")
  expect_identical(kept$w, "OTHR")
  expect_length(.nr_dist(conn), 4)
})

test_that("frs_near_river reports rows measured and rows with no local code", {
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  .nr_fixture(conn, .nr_tributary())
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.nr_near")
  out <- capture.output(frs_near_river(conn, "pg_temp.nr_streams",
    "pg_temp.nr_near", discharge_min = 3, distance_max = 1000))
  expect_match(out[1], "4 segments within 1000 m; 0 with no local code did not walk")
  # A row with no local code cannot walk, and is counted.
  DBI::dbExecute(conn, "UPDATE pg_temp.nr_streams SET localcode_ltree = NULL
                        WHERE id_segment = 13")
  out_nc <- capture.output(frs_near_river(conn, "pg_temp.nr_streams",
    "pg_temp.nr_near", discharge_min = 3, distance_max = 1000))
  expect_match(out_nc[1], "3 segments within 1000 m; 1 with no local code")
  expect_false("13" %in% names(.nr_dist(conn)))
  # Row 1 is the river's bottom row (local code = watershed code), which
  # FWA_Downstream() calls downstream of any deeper code whatever the
  # origin's local code: a row with no local code must still not walk.
  DBI::dbExecute(conn, "UPDATE pg_temp.nr_streams SET localcode_ltree = '100'
                        WHERE id_segment = 1")
  nr_run(conn, d = 5000)
  expect_false("13" %in% names(.nr_dist(conn)))
})

test_that("frs_near_river validates its inputs", {
  expect_error(frs_near_river(NULL, "a.b", "a.c", 0, 10), "discharge_min")
  expect_error(frs_near_river(NULL, "a.b", "a.c", c(3, 3), c(1, 1)),
               "distinct")
  expect_error(frs_near_river(NULL, "a.b", "a.c", 3, c(1, 2)), "one per")
  expect_error(frs_near_river(NULL, "a.b", "a.c", 3, Inf), "distance_max")
  expect_error(frs_near_river(NULL, "a;b", "a.c", 3, 1), "invalid characters")
  skip_if_no_conn()
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  segs <- .nr_tributary()
  .nr_fixture(conn, segs)
  DBI::dbExecute(conn, "ALTER TABLE pg_temp.nr_streams DROP COLUMN mad_m3s")
  expect_error(nr_run(conn), "no mad_m3s column.*frs_col_join")
})
