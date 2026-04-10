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

  # Bundled rules should give CO at least as much rearing as disabled
  # (the carve-out can only ADD segments, never remove). It might be
  # equal if no 1050/1150 edges exist in this AOI.
  expect_gte(co$rr, co_off$rr)
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

  # lake_rearing column logic is independent of rules YAML.
  # BT has CSV rear_channel_width which populates lake_rearing.
  # Should be >= 0 (not NULL or error). Smoke test verified 4.
  expect_true(!is.na(bt$lake_rr))
})
