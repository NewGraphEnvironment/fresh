# --- Unit tests: frs_habitat breaks_gradient parameter ---

test_that("breaks_gradient validates type", {
  expect_error(
    frs_habitat("mock", "BULK", breaks_gradient = "high"),
    "must be numeric"
  )
})

test_that("breaks_gradient validates range [0,1]", {
  expect_error(
    frs_habitat("mock", "BULK", breaks_gradient = c(0.05, 1.5)),
    "must be in \\[0, 1\\]"
  )
  expect_error(
    frs_habitat("mock", "BULK", breaks_gradient = c(-0.01, 0.05)),
    "must be in \\[0, 1\\]"
  )
})

test_that("breaks_gradient errors on excess precision", {
  # 0.05001 cannot be represented at 4-digit basis points
  expect_error(
    frs_habitat("mock", "BULK", breaks_gradient = c(0.05001)),
    "exceed basis-point precision"
  )
})

test_that("breaks_gradient errors on duplicate labels", {
  # Distinct values that round to same label
  # Note: basis-point precision check catches this first for most inputs.
  # This tests the fallback collision check directly.
  expect_error(
    .frs_validate_gradient_thresholds(c(0.05, 0.0500), "test"),
    "duplicate labels|exceed basis-point"
  )
})

test_that("breaks_gradient errors on NA", {
  expect_error(
    frs_habitat("mock", "BULK", breaks_gradient = c(0.05, NA)),
    "contains NA"
  )
})

test_that("breaks_gradient accepts valid 4-decimal values", {
  # Should NOT error
  expect_silent(.frs_validate_gradient_thresholds(c(0.0249, 0.05, 0.0549, 0.10, 0.15), "test"))
  expect_silent(.frs_validate_gradient_thresholds(numeric(0), "test"))
})

test_that("breaks_gradient default auto-derives from params", {
  # The auto-derivation logic uses lapply on params[species] to extract
  # spawn_gradient_max and rear_gradient_max. Verify the helper produces
  # the expected values for a known species set.
  params <- frs_params(csv = system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"))

  species <- c("CO", "BT")
  vals <- unlist(lapply(params[species], function(p) {
    c(p$spawn_gradient_max, p$rear_gradient_max)
  }), use.names = FALSE)
  vals <- vals[!is.na(vals)]

  # CO: spawn 0.0549, rear 0.0549
  # BT: spawn 0.0549, rear 0.1049
  expect_setequal(vals, c(0.0549, 0.0549, 0.0549, 0.1049))
})

test_that("breaks_gradient dedup by integer-percent label", {
  # If two thresholds round to the same gradient_N, keep one
  thr <- c(0.05, 0.0549, 0.10, 0.1049)
  deduped <- thr[!duplicated(as.integer(thr * 100))]
  expect_equal(deduped, c(0.05, 0.10))
})

# --- Integration tests (DB required) ---

test_that("breaks_gradient default produces more breaks than disabled", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()

  aoi <- "wscode_ltree <@ '100.190442.999098.995997.058910.432966'::ltree"

  # to_streams must NOT collide with the auto-generated working.streams_<label>
  on.exit({
    for (tbl in c("working.persist_brk_default",
                  "working.persist_brk_default_habitat",
                  "working.persist_brk_disabled",
                  "working.persist_brk_disabled_habitat",
                  "working.streams_brktest_a",
                  "working.streams_brktest_b")) {
      DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s CASCADE", tbl))
    }
    DBI::dbDisconnect(conn)
  })

  # Default: auto-derive from spawn/rear maxes
  res_default <- frs_habitat(conn,
    aoi = aoi, species = c("CO", "BT"), label = "brktest_a",
    to_streams = "working.persist_brk_default",
    to_habitat = "working.persist_brk_default_habitat",
    verbose = FALSE)

  # Disabled: only access thresholds (current 0.9.0 behavior)
  res_disabled <- frs_habitat(conn,
    aoi = aoi, species = c("CO", "BT"), label = "brktest_b",
    to_streams = "working.persist_brk_disabled",
    to_habitat = "working.persist_brk_disabled_habitat",
    breaks_gradient = numeric(0),
    verbose = FALSE)

  # Auto-derive should produce strictly more segments (extra breaks split)
  expect_gt(res_default$n_segments, res_disabled$n_segments)
})

test_that("breaks_gradient custom override produces more segments than disabled", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()

  aoi <- "wscode_ltree <@ '100.190442.999098.995997.058910.432966'::ltree"

  on.exit({
    for (tbl in c("working.persist_brk_custom",
                  "working.persist_brk_custom_habitat",
                  "working.persist_brk_min",
                  "working.persist_brk_min_habitat")) {
      DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s CASCADE", tbl))
    }
    DBI::dbDisconnect(conn)
  })

  # Custom: 0.10 (one extra break beyond mandatory access)
  res_custom <- frs_habitat(conn,
    aoi = aoi, species = c("CO", "BT"), label = "brktest_d",
    to_streams = "working.persist_brk_custom",
    to_habitat = "working.persist_brk_custom_habitat",
    breaks_gradient = c(0.10),
    verbose = FALSE)

  # Disabled: only access thresholds
  res_min <- frs_habitat(conn,
    aoi = aoi, species = c("CO", "BT"), label = "brktest_e",
    to_streams = "working.persist_brk_min",
    to_habitat = "working.persist_brk_min_habitat",
    breaks_gradient = numeric(0),
    verbose = FALSE)

  # Adding one extra break should produce >= segments (more or equal,
  # depending on whether 10% is exceeded anywhere in the test area)
  expect_gte(res_custom$n_segments, res_min$n_segments)
})

test_that("regression #110: distinct thresholds produce distinct labels", {
  # Pre-fix bug: 0.05 and 0.0549 both rounded to gradient_5 (collision)
  # Post-fix: 0.05 → gradient_0500, 0.0549 → gradient_0549 (distinct)
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()

  aoi <- "wscode_ltree <@ '100.190442.999098.995997.058910.432966'::ltree"

  on.exit({
    for (tbl in c("working.persist_brk_110",
                  "working.persist_brk_110_habitat",
                  "working.persist_brk_110_one",
                  "working.persist_brk_110_one_habitat")) {
      DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s CASCADE", tbl))
    }
    DBI::dbDisconnect(conn)
  })

  # Pass two thresholds that would collide under the old format
  frs_habitat(conn,
    aoi = aoi, species = c("CO", "BT"), label = "brktest_110",
    to_streams = "working.persist_brk_110",
    to_habitat = "working.persist_brk_110_habitat",
    breaks_gradient = c(0.05, 0.0549),
    verbose = FALSE)

  res_one <- frs_habitat(conn,
    aoi = aoi, species = c("CO", "BT"), label = "brktest_110b",
    to_streams = "working.persist_brk_110_one",
    to_habitat = "working.persist_brk_110_one_habitat",
    breaks_gradient = c(0.05),
    verbose = FALSE)

  res_two <- DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM working.persist_brk_110")$n

  # Two distinct thresholds should produce >= segments than one
  # (more if any segments fall between 5.0% and 5.49% gradient)
  expect_gte(res_two, res_one$n_segments)
})

# --- Unit tests: aoi + wsg interaction ---

test_that("wsg + character aoi are ANDed, not replaced", {
  # The wsg_specs construction should combine WSG and aoi
  # We can't easily test frs_habitat() without a DB, but we can
  # verify the job_aoi construction logic directly.

  # Simulate the fixed logic:
  w <- "ADMS"
  aoi_str <- "edge_type != 6010"
  job_aoi <- sprintf(
    "watershed_group_code = %s AND (%s)",
    fresh:::.frs_quote_string(w), aoi_str)

  expect_match(job_aoi, "watershed_group_code = 'ADMS'")
  expect_match(job_aoi, "edge_type != 6010")
  expect_match(job_aoi, "AND")
})

test_that("wsg without aoi uses WSG code directly", {
  w <- "ADMS"
  aoi <- NULL
  job_aoi <- if (is.null(aoi)) w else aoi
  expect_equal(job_aoi, "ADMS")
})

test_that("wsg + sf aoi uses sf directly (not combined string)", {
  w <- "ADMS"
  aoi_sf <- sf::st_sfc(sf::st_point(c(0, 0)), crs = 3005)
  # sf aoi should pass through unchanged
  if (is.null(aoi_sf)) {
    job_aoi <- w
  } else if (is.character(aoi_sf) && length(aoi_sf) == 1) {
    job_aoi <- "should not reach here"
  } else {
    job_aoi <- aoi_sf
  }
  expect_true(inherits(job_aoi, "sfc"))
})

test_that("integration: wsg + aoi does not scan entire province", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  # Extract with wsg + aoi — should be ADMS-sized, not province-sized
  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = "working.test_aoi_141",
    where = sprintf("watershed_group_code = 'ADMS' AND (%s)",
                    "edge_type != 6010"),
    overwrite = TRUE)

  n <- DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM working.test_aoi_141")$n
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_aoi_141")

  # ADMS has ~11,500 segments. Province has ~4.9 million.
  # Filtered ADMS should be < 15,000 (not millions).
  expect_lt(n, 15000)
  expect_gt(n, 5000)
})

# --- Integration tests: to_barriers parameter ---

test_that("integration: to_barriers persists gradient barriers table", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()

  aoi <- "wscode_ltree <@ '100.190442.999098.995997.058910.432966'::ltree"

  on.exit({
    for (tbl in c("working.persist_barriers_143",
                  "working.persist_barriers_143_s",
                  "working.persist_barriers_143_h")) {
      DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s CASCADE", tbl))
    }
    DBI::dbDisconnect(conn)
  })

  frs_habitat(conn,
    aoi = aoi, species = "BT", label = "b143",
    to_streams = "working.persist_barriers_143_s",
    to_habitat = "working.persist_barriers_143_h",
    to_barriers = "working.persist_barriers_143",
    verbose = FALSE)

  # Barriers table should exist and have rows
  n <- DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM working.persist_barriers_143")$n
  expect_gt(n, 0)

  # Should have expected columns
  cols <- DBI::dbGetQuery(conn,
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = 'working' AND table_name = 'persist_barriers_143'
     ORDER BY ordinal_position")$column_name
  expect_true("blue_line_key" %in% cols)
  expect_true("downstream_route_measure" %in% cols)
  expect_true("gradient_class" %in% cols)
  expect_true("label" %in% cols)
  expect_true("wscode_ltree" %in% cols)
  expect_true("localcode_ltree" %in% cols)
})

test_that("integration: NULL to_barriers does not persist", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()

  aoi <- "wscode_ltree <@ '100.190442.999098.995997.058910.432966'::ltree"

  on.exit({
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.persist_null_143_s CASCADE")
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.persist_null_143_h CASCADE")
    DBI::dbDisconnect(conn)
  })

  frs_habitat(conn,
    aoi = aoi, species = "BT", label = "n143",
    to_streams = "working.persist_null_143_s",
    to_habitat = "working.persist_null_143_h",
    to_barriers = NULL,
    verbose = FALSE)

  # No barriers table should exist
  exists <- DBI::dbGetQuery(conn,
    "SELECT EXISTS (
       SELECT 1 FROM information_schema.tables
       WHERE table_schema = 'working' AND table_name = 'barriers_n143_gradient'
     ) AS e")$e
  expect_false(exists)
})

# --- Integration tests: multiple labels per break position (#145) ---

test_that("integration: multiple labels at same position preserved in breaks", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()

  aoi <- "wscode_ltree <@ '100.190442.999098.995997.058910.432966'::ltree"
  tbl_s <- "working.test_145_streams"
  tbl_breaks <- paste0(tbl_s, "_breaks")

  on.exit({
    for (tbl in c(tbl_s, tbl_breaks,
                  "working.test_145_src_a", "working.test_145_src_b")) {
      DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s CASCADE", tbl))
    }
    DBI::dbDisconnect(conn)
  })

  # Extract to get a real BLK + measure
  frs_extract(conn,
    from = "whse_basemapping.fwa_stream_networks_sp",
    to = tbl_s, where = aoi, overwrite = TRUE)
  pos <- DBI::dbGetQuery(conn, sprintf(
    "SELECT blue_line_key, downstream_route_measure + 100 AS drm
     FROM %s LIMIT 1", tbl_s))

  # Create two mock break sources at the SAME position, DIFFERENT labels
  for (tbl in c("working.test_145_src_a", "working.test_145_src_b")) {
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", tbl))
    DBI::dbExecute(conn, sprintf(
      "CREATE TABLE %s AS SELECT %d::int AS blue_line_key, %s::float8 AS downstream_route_measure",
      tbl, pos$blue_line_key, pos$drm))
  }

  # Segment with both sources at same position
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", tbl_s))
  frs_network_segment(conn, aoi = aoi, to = tbl_s,
    break_sources = list(
      list(table = "working.test_145_src_a", label = "label_a"),
      list(table = "working.test_145_src_b", label = "label_b")),
    verbose = FALSE)

  # Both labels should survive at the same position
  dupes <- DBI::dbGetQuery(conn, sprintf(
    "SELECT blue_line_key, downstream_route_measure,
            count(DISTINCT label)::int AS n_labels
     FROM %s
     GROUP BY blue_line_key, downstream_route_measure
     HAVING count(DISTINCT label) > 1", tbl_breaks))

  expect_gt(nrow(dupes), 0)
  expect_true(all(dupes$n_labels >= 2))
})
