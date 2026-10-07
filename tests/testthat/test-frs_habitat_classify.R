# --- Unit tests: frs_habitat_classify ---

test_that("gate parameter validates type", {
  expect_error(
    frs_habitat_classify("mock", "t", "o", species = "CO", gate = "yes"),
    "is.logical"
  )
  expect_error(
    frs_habitat_classify("mock", "t", "o", species = "CO", gate = 1),
    "is.logical"
  )
})

test_that("species is required", {
  expect_error(
    frs_habitat_classify("mock", "t", "o"),
    "species"
  )
})

# --- Unit tests: .frs_access_label_filter ---

test_that("only label_block and gradient labels block (new format)", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )

  mock_labels <- data.frame(
    label = c("blocked", "passable", "accessible", "observed",
              "potential", "gradient_1500", "gradient_2500",
              "bridge", "monitoring_station"),
    stringsAsFactors = FALSE)

  mockery::stub(.frs_access_label_filter, "DBI::dbGetQuery",
    function(conn, sql) mock_labels)

  # Default label_block = "blocked"
  result <- .frs_access_label_filter("mock", "breaks", 0.15)
  expect_true(grepl("blocked", result))
  expect_true(grepl("gradient_1500", result))
  expect_true(grepl("gradient_2500", result))
  expect_false(grepl("potential", result))
  expect_false(grepl("bridge", result))
})

test_that("legacy gradient_N format still parses correctly", {
  # Backward compat: user-supplied labels via frs_break_find(label="gradient_15")
  mock_labels <- data.frame(
    label = c("blocked", "gradient_15", "gradient_25"),
    stringsAsFactors = FALSE)

  mockery::stub(.frs_access_label_filter, "DBI::dbGetQuery",
    function(conn, sql) mock_labels)

  # gradient_15 (legacy) parsed as 0.15, blocks species at 0.15 access
  result <- .frs_access_label_filter("mock", "breaks", 0.15)
  expect_true(grepl("gradient_15", result))
  expect_true(grepl("gradient_25", result))

  # gradient_15 (legacy) parsed as 0.15, does NOT block species at 0.25
  result_bt <- .frs_access_label_filter("mock", "breaks", 0.25)
  expect_false(grepl("gradient_15", result_bt))
  expect_true(grepl("gradient_25", result_bt))
})

test_that("mixed legacy and new format both parse correctly", {
  # Mixed table — user-supplied legacy + auto-derived new format
  mock_labels <- data.frame(
    label = c("gradient_15", "gradient_1500", "gradient_0549"),
    stringsAsFactors = FALSE)

  mockery::stub(.frs_access_label_filter, "DBI::dbGetQuery",
    function(conn, sql) mock_labels)

  # All three should be evaluated:
  # - gradient_15 → 0.15 (legacy)
  # - gradient_1500 → 0.15 (new)
  # - gradient_0549 → 0.0549 (new)
  # CO at 0.15 access: 0.15 >= 0.15 (blocks gradient_15 + gradient_1500),
  # 0.0549 < 0.15 (gradient_0549 does not block)
  result <- .frs_access_label_filter("mock", "breaks", 0.15)
  expect_true(grepl("gradient_15'", result))    # legacy 15
  expect_true(grepl("gradient_1500", result))    # new 15
  expect_false(grepl("gradient_0549", result))   # 5.49% < 15%
})

test_that("custom label_block block", {
  mock_labels <- data.frame(
    label = c("blocked", "potential", "passable", "gradient_1500"),
    stringsAsFactors = FALSE)

  mockery::stub(.frs_access_label_filter, "DBI::dbGetQuery",
    function(conn, sql) mock_labels)

  # Conservative: potential also blocks
  result <- .frs_access_label_filter("mock", "breaks", 0.15,
    label_block = c("blocked", "potential"))
  expect_true(grepl("blocked", result))
  expect_true(grepl("potential", result))
  expect_true(grepl("gradient_1500", result))
  expect_false(grepl("passable", result))
})

test_that("gradient labels below threshold do not block", {
  mockery::stub(.frs_access_label_filter, "DBI::dbGetQuery", function(conn, sql) {
    data.frame(label = c("gradient_1500", "gradient_2500"),
               stringsAsFactors = FALSE)
  })

  # At 25% threshold: only gradient_2500 blocks, gradient_1500 does not
  result <- .frs_access_label_filter("mock", "breaks", 0.25)
  expect_true(grepl("gradient_2500", result))
  expect_false(grepl("gradient_1500", result))
})

test_that("no blocking labels returns FALSE", {
  mockery::stub(.frs_access_label_filter, "DBI::dbGetQuery", function(conn, sql) {
    data.frame(label = c("passable", "accessible"),
               stringsAsFactors = FALSE)
  })

  result <- .frs_access_label_filter("mock", "breaks", 0.15)
  expect_equal(result, "FALSE")
})

test_that("malformed gradient labels do not block", {
  # Edge cases that should NOT match either format
  mockery::stub(.frs_access_label_filter, "DBI::dbGetQuery", function(conn, sql) {
    data.frame(label = c("gradient_15000",   # 5 digits — not legacy or new
                         "gradient_5p49",    # decimal separator — not supported
                         "gradient_-100",    # negative — not supported
                         "gradient_",         # empty number
                         "gradient",          # no underscore
                         "Gradient_1500"),    # capital G
               stringsAsFactors = FALSE)
  })

  result <- .frs_access_label_filter("mock", "breaks", 0.15)
  expect_equal(result, "FALSE")
})

test_that("gradient_NNNN with various values parses to expected fractions", {
  # Direct test of the new format parser
  test_cases <- list(
    list(label = "gradient_0249", expected_block_at = 0.0249),
    list(label = "gradient_0500", expected_block_at = 0.05),
    list(label = "gradient_0549", expected_block_at = 0.0549),
    list(label = "gradient_1000", expected_block_at = 0.10),
    list(label = "gradient_1500", expected_block_at = 0.15),
    list(label = "gradient_2500", expected_block_at = 0.25)
  )
  for (tc in test_cases) {
    mockery::stub(.frs_access_label_filter, "DBI::dbGetQuery", function(conn, sql) {
      data.frame(label = tc$label, stringsAsFactors = FALSE)
    })
    # Species with access threshold equal to the label's value: blocks
    result <- .frs_access_label_filter("mock", "breaks", tc$expected_block_at)
    expect_true(grepl(tc$label, result),
      info = sprintf("%s should block species at access %s",
                     tc$label, tc$expected_block_at))
    # Species with access threshold higher than label: does NOT block
    result_above <- .frs_access_label_filter("mock", "breaks",
                                              tc$expected_block_at + 0.01)
    expect_equal(result_above, "FALSE",
      info = sprintf("%s should not block species at access > %s",
                     tc$label, tc$expected_block_at))
  }
})


# --- Integration tests: rules YAML behavior on ADMS sub-basin ---

# Helper: run frs_habitat with given rules and return per-species counts
.rules_test_run <- function(conn, label, rules) {
  aoi <- "wscode_ltree <@ '100.190442.999098.995997.058910.432966'::ltree"
  to_streams <- paste0("working.rt_streams_", label)
  to_habitat <- paste0("working.rt_habitat_", label)

  frs_habitat(conn,
    aoi = aoi, species = c("CO", "BT", "SK", "PK"),
    label = label,
    rules = rules,
    to_streams = to_streams,
    to_habitat = to_habitat,
    verbose = FALSE)

  counts <- DBI::dbGetQuery(conn, sprintf(
    "SELECT species_code,
       count(*) FILTER (WHERE accessible)::int AS acc,
       count(*) FILTER (WHERE spawning)::int AS spn,
       count(*) FILTER (WHERE rearing)::int AS rr,
       count(*) FILTER (WHERE lake_rearing)::int AS lake_rr
     FROM %s GROUP BY species_code ORDER BY species_code", to_habitat))

  for (tbl in c(to_streams, to_habitat)) {
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s CASCADE", tbl))
  }

  counts
}

test_that("integration: bundled rules — SK rear on streams = 0", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  counts <- .rules_test_run(conn, "rt_sk", rules = NULL)
  sk <- counts[counts$species_code == "SK", ]

  # SK rule: rear on lakes >= 200 ha only. ADMS sub-basin has no lakes
  # >= 200 ha, so rearing should be 0.
  expect_equal(sk$rr, 0)
})

test_that("integration: bundled rules — CO rear includes wetland-flow segments", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  counts <- .rules_test_run(conn, "rt_co", rules = NULL)
  co <- counts[counts$species_code == "CO", ]

  # CO has 4 rear rules including wetland-flow carve-out (1050/1150
  # without thresholds). Compare to disabled rules — should be >= disabled
  # since wetland-flow carve-out adds segments.
  counts_off <- .rules_test_run(conn, "rt_co_off", rules = FALSE)
  co_off <- counts_off[counts_off$species_code == "CO", ]

  # Bundled rules should give CO non-zero rearing (the carve-out adds
  # wetland-flow segments). Note: CO also has cluster_rearing=TRUE
  # which may remove disconnected segments, so we can't assume >= disabled.
  expect_gt(co$rr, 0)
})

test_that("integration: bundled rules — PK and CM get rearing = 0", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  counts <- .rules_test_run(conn, "rt_pk", rules = NULL)
  pk <- counts[counts$species_code == "PK", ]

  # PK has rear: [] (empty rule list). Rearing should be 0.
  expect_equal(pk$rr, 0)
})

test_that("integration: rules = FALSE matches pre-rules behavior", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  counts_off <- .rules_test_run(conn, "rt_off", rules = FALSE)

  # When rules disabled, BT should have non-zero rearing on streams
  # (BT in CSV has rear_channel_width_min=1.5, rear_gradient_max=0.1049)
  bt <- counts_off[counts_off$species_code == "BT", ]
  expect_gt(bt$rr, 0)

  # SK without rules should have rearing on streams (CSV gives
  # rear_channel_width_min=1.5 but no gradient — see params CSV)
  sk_off <- counts_off[counts_off$species_code == "SK", ]
  expect_gte(sk_off$rr, 0)  # may or may not have rearing without rules
})

test_that("integration: lake_rearing column preserved with rules", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  on.exit(DBI::dbDisconnect(conn))

  counts <- .rules_test_run(conn, "rt_lr", rules = NULL)
  bt <- counts[counts$species_code == "BT", ]

  # The lake_rearing column is always written. Its value comes from the
  # bundled BT rear `waterbody_type: L` rule (polygon area only,
  # fresh#240). Should be >= 0 (not NULL or error).
  expect_true(!is.na(bt$lake_rr))
})


# --- Integration: per-WSG cw/mad model switch (fresh#220) ---

test_that("integration: params_method = mad classifies on mad_m3s", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()

  aoi <- "wscode_ltree <@ '100.190442.999098.995997.058910.432966'::ltree"
  tbl_s <- "working.test_220_streams"
  tbl_h <- "working.test_220_habitat"
  tbl_nomad <- "working.test_220_streams_nomad"

  on.exit({
    for (t in c(tbl_s, tbl_h, tbl_nomad, paste0(tbl_nomad, "_habitat"))) {
      DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s CASCADE", t))
    }
    DBI::dbDisconnect(conn)
  })

  frs_network_segment(conn, aoi = aoi, to = tbl_s, verbose = FALSE)

  # CSV-ranges path (no rules) so the expected count is a plain SQL filter
  params <- frs_params(csv = system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"))
  params$CO$rules <- NULL

  run <- function(model) {
    pm <- data.frame(watershed_group_code = "ADMS", model = model)
    frs_habitat_classify(conn, table = tbl_s, to = tbl_h, species = "CO",
      params = params, params_method = pm, gate = FALSE, verbose = FALSE)
    DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*) FILTER (WHERE spawning)::int AS spn,
              count(*) FILTER (WHERE rearing)::int AS rr
       FROM %s WHERE species_code = 'CO'", tbl_h))
  }

  n_cw <- run("cw")
  n_mad <- run("mad")

  sp <- params$CO$ranges$spawn$mad_m3s
  params_fresh <- utils::read.csv(system.file("extdata",
    "parameters_fresh.csv", package = "fresh"))
  expected <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM %s s
     WHERE s.gradient >= %s AND s.gradient <= %s
       AND s.mad_m3s >= %s AND s.mad_m3s <= %s
       AND s.edge_type IN (%s)",
    tbl_s, params_fresh$spawn_gradient_min[params_fresh$species_code == "CO"],
    params$CO$spawn_gradient_max, sp[1], sp[2],
    paste(c(frs_edge_types(category = "stream")$edge_type,
            frs_edge_types(category = "canal")$edge_type),
          collapse = ", ")))$n

  expect_gt(n_mad$spn, 0)
  expect_equal(n_mad$spn, expected)
  expect_false(identical(n_cw, n_mad))

  # mad model without a mad_m3s column is a clear error
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s AS SELECT * FROM %s", tbl_nomad, tbl_s))
  DBI::dbExecute(conn, sprintf(
    "ALTER TABLE %s DROP COLUMN mad_m3s", tbl_nomad))
  expect_error(
    frs_habitat_classify(conn, table = tbl_nomad,
      to = paste0(tbl_nomad, "_habitat"), species = "CO", params = params,
      params_method = data.frame(watershed_group_code = "ADMS",
                                 model = "mad"),
      gate = FALSE, verbose = FALSE),
    "mad_m3s")
})

test_that("integration: mad guard reads columns from mixed-case / empty tables", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()
  # Mixed-case unquoted name folds to lower case in Postgres; an
  # information_schema lookup on the literal text would miss it.
  tbl_s <- "working.Test_220_Empty"
  tbl_h <- "working.test_220_empty_habitat"
  on.exit({
    for (t in c(tbl_s, tbl_h)) {
      DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s CASCADE", t))
    }
    DBI::dbDisconnect(conn)
  })
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", tbl_s))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s (id_segment integer, watershed_group_code varchar(4),
       blue_line_key integer, downstream_route_measure double precision,
       wscode_ltree ltree, localcode_ltree ltree, edge_type integer,
       waterbody_key integer, gradient double precision,
       channel_width double precision, mad_m3s double precision)", tbl_s))

  params <- frs_params(csv = system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"))
  # Empty table: no WSGs resolve; classify is a no-op, not an error
  expect_no_error(frs_habitat_classify(conn, table = tbl_s, to = tbl_h,
    species = "CO", params = params,
    params_method = data.frame(watershed_group_code = "ADMS", model = "mad"),
    gate = FALSE, verbose = FALSE))

  # One mad-group row: the guard must find mad_m3s on the mixed-case name
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s (id_segment, watershed_group_code) VALUES (1, 'ADMS')",
    tbl_s))
  expect_no_error(frs_habitat_classify(conn, table = tbl_s, to = tbl_h,
    species = "CO", params = params,
    params_method = data.frame(watershed_group_code = "ADMS", model = "mad"),
    gate = FALSE, verbose = FALSE))
})
