# --- Unit tests: frs_cluster ---

test_that("direction validates", {
  expect_error(
    frs_cluster("mock", "t", "h", direction = "sideways"),
    "direction"
  )
})

test_that("label_cluster must be character scalar", {
  expect_error(
    frs_cluster("mock", "t", "h", label_cluster = 123),
    "invalid characters"
  )
  expect_error(
    frs_cluster("mock", "t", "h", label_cluster = c("a", "b")),
    "length"
  )
})

test_that("label_connect must be character scalar", {
  expect_error(
    frs_cluster("mock", "t", "h", label_connect = TRUE),
    "is.character"
  )
})

test_that("bridge_gradient must be numeric scalar", {
  expect_error(
    frs_cluster("mock", "t", "h", bridge_gradient = "high"),
    "is.numeric"
  )
})

test_that("bridge_distance must be numeric scalar", {
  expect_error(
    frs_cluster("mock", "t", "h", bridge_distance = "far"),
    "is.numeric"
  )
})

test_that("confluence_m must be numeric scalar", {
  expect_error(
    frs_cluster("mock", "t", "h", confluence_m = "ten"),
    "is.numeric"
  )
})

test_that("identifier validation catches bad names", {
  expect_error(
    frs_cluster("mock", "t; DROP TABLE", "h"),
    "invalid characters"
  )
  expect_error(
    frs_cluster("mock", "t", "h", label_cluster = "col; --"),
    "invalid characters"
  )
})

# --- Unit tests: upstream SQL pattern ---

test_that("upstream SQL includes FWA_Upstream and confluence check", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  mockery::stub(frs_cluster, "DBI::dbGetQuery", function(conn, sql) {
    if (grepl("DISTINCT species_code", sql)) {
      return(data.frame(species_code = "CO", stringsAsFactors = FALSE))
    }
    data.frame(n = 10L)
  })

  frs_cluster("mock", "fresh.streams", "fresh.habitat",
    species = "CO", direction = "upstream", verbose = FALSE)

  expect_length(sql_log, 1)
  expect_match(sql_log[1], "ST_ClusterDBSCAN")
  expect_match(sql_log[1], "FWA_Upstream")
  expect_match(sql_log[1], "subpath")
  expect_match(sql_log[1], "cluster_minimums")
  expect_match(sql_log[1], "SET rearing = FALSE")
})

# --- Unit tests: downstream SQL pattern ---

test_that("downstream SQL includes fwa_downstreamtrace and gradient bridge", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    }
  )

  mockery::stub(frs_cluster, "DBI::dbGetQuery", function(conn, sql) {
    if (grepl("DISTINCT species_code", sql)) {
      return(data.frame(species_code = "CO", stringsAsFactors = FALSE))
    }
    data.frame(n = 10L)
  })

  frs_cluster("mock", "fresh.streams", "fresh.habitat",
    species = "CO", direction = "downstream", verbose = FALSE)

  expect_length(sql_log, 1)
  expect_match(sql_log[1], "ST_ClusterDBSCAN")
  expect_match(sql_log[1], "fwa_downstreamtrace")
  expect_match(sql_log[1], "watershed_key")
  expect_match(sql_log[1], "nearest_connect")
  expect_match(sql_log[1], "nearest_barrier")
  expect_match(sql_log[1], "0.05")
  expect_match(sql_log[1], "10000")
})

# --- Unit tests: both direction uses temp tables ---

test_that("both direction creates temp table and evaluates independently", {
  sql_log <- character(0)
  local_mocked_bindings(
    .frs_db_execute = function(conn, sql) {
      sql_log <<- c(sql_log, sql)
      0L
    },
    .frs_cluster_both = function(conn, table, habitat, label_cluster,
                                 label_connect, species, confluence_m,
                                 bridge_gradient, bridge_distance) {
      # Just verify it's called with the right species
      sql_log <<- c(sql_log, paste("BOTH:", species))
    }
  )

  mockery::stub(frs_cluster, "DBI::dbGetQuery", function(conn, sql) {
    data.frame(n = 10L)
  })

  frs_cluster("mock", "fresh.streams", "fresh.habitat",
    species = "CO", direction = "both", verbose = FALSE)

  expect_true(any(grepl("BOTH: CO", sql_log)))
})

# --- Integration tests (DB required) ---

test_that("frs_cluster upstream removes disconnected rearing", {
  skip_if_not(.frs_db_available(), "DB not available")
  conn <- frs_db_conn()

  tbl_streams <- "working.test_cluster_streams"
  tbl_habitat <- "working.test_cluster_habitat"
  on.exit({
    .frs_test_drop(conn, tbl_habitat)
    .frs_test_drop(conn, tbl_streams)
    .frs_test_drop(conn, paste0(tbl_streams, "_breaks"))
    DBI::dbDisconnect(conn)
  })

  # ADMS sub-basin: 188 segments, small enough for fast test
  aoi <- "wscode_ltree <@ '100.190442.999098.995997.058910.432966'::ltree"

  # Segment network with gradient barriers
  frs_network_segment(conn, aoi = aoi, to = tbl_streams,
    break_sources = list(
      list(table = "whse_basemapping.fwa_obstructions_sp",
           where = "obstruction_type = 'Falls'",
           label = "blocked",
           col_measure = "route_measure")
    ), verbose = FALSE)

  # Classify CO habitat

  frs_habitat_classify(conn,
    table = tbl_streams, to = tbl_habitat,
    species = "CO", gate = FALSE, verbose = FALSE)

  # Count rearing before cluster analysis
  n_before <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*) FILTER (WHERE rearing)::int AS n FROM %s
     WHERE species_code = 'CO'", tbl_habitat))$n

  # Run upstream cluster check
  frs_cluster(conn, table = tbl_streams, habitat = tbl_habitat,
    label_cluster = "rearing", label_connect = "spawning",
    species = "CO", direction = "upstream", verbose = FALSE)

  n_after <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*) FILTER (WHERE rearing)::int AS n FROM %s
     WHERE species_code = 'CO'", tbl_habitat))$n

  # Cluster analysis should remove some or keep all — never add
  expect_true(n_after <= n_before)
})
