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

test_that("only blocked and gradient labels block", {
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) 0L
  )

  # Mock the label query
  mockery::stub(.frs_access_label_filter, "DBI::dbGetQuery", function(conn, sql) {
    data.frame(label = c("blocked", "passable", "accessible", "observed",
                          "potential", "gradient_15", "gradient_25",
                          "bridge", "monitoring_station"),
               stringsAsFactors = FALSE)
  })

  # At 15% threshold: "blocked" + gradient_15 + gradient_25 block.
  # Everything else does NOT block.
  result <- .frs_access_label_filter("mock", "breaks", 0.15)
  expect_true(grepl("blocked", result))
  expect_true(grepl("gradient_15", result))
  expect_true(grepl("gradient_25", result))
  expect_false(grepl("passable", result))
  expect_false(grepl("accessible", result))
  expect_false(grepl("observed", result))
  expect_false(grepl("potential", result))
  expect_false(grepl("bridge", result))
  expect_false(grepl("monitoring_station", result))
})

test_that("gradient labels below threshold do not block", {
  mockery::stub(.frs_access_label_filter, "DBI::dbGetQuery", function(conn, sql) {
    data.frame(label = c("gradient_15", "gradient_25"),
               stringsAsFactors = FALSE)
  })

  # At 25% threshold: only gradient_25 blocks, gradient_15 does not
  result <- .frs_access_label_filter("mock", "breaks", 0.25)
  expect_true(grepl("gradient_25", result))
  expect_false(grepl("gradient_15", result))
})

test_that("no blocking labels returns FALSE", {
  mockery::stub(.frs_access_label_filter, "DBI::dbGetQuery", function(conn, sql) {
    data.frame(label = c("passable", "accessible"),
               stringsAsFactors = FALSE)
  })

  result <- .frs_access_label_filter("mock", "breaks", 0.15)
  expect_equal(result, "FALSE")
})
