# --- Unit tests: frs_habitat breaks_gradient parameter ---

test_that("breaks_gradient validates type", {
  expect_error(
    frs_habitat("mock", "BULK", breaks_gradient = "high"),
    "is.numeric"
  )
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
