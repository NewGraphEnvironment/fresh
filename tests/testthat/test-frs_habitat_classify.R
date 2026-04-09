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
