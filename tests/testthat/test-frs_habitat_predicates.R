# Unit tests: frs_habitat_predicates
#
# Pure-R helper — no DB needed. Builds a single-species params list
# and checks the SQL strings emitted for each habitat type.

# Helper: minimal sp_params with rules path
sp_with_rules <- function(species = "CO",
                          rules = NULL,
                          rear_cw = c(1.5, 9999),
                          spawn_cw = c(2, 9999),
                          spawn_grad_max = 0.0549,
                          spawn_grad_min = 0,
                          rear_grad_max = 0.0849) {
  list(
    species_code = species,
    access_gradient = 0.15,
    spawn_gradient_max = spawn_grad_max,
    spawn_gradient_min = spawn_grad_min,
    params_sp = list(
      ranges = list(
        spawn = list(
          channel_width = spawn_cw,
          gradient = c(0, spawn_grad_max)),
        rear = list(
          channel_width = rear_cw,
          gradient = c(0, rear_grad_max))
      ),
      spawn_edge_types = "stream,canal",
      rear_edge_types = "stream,canal",
      rules = rules
    )
  )
}

# -- Spawn predicate: rules path ---------------------------------------------

test_that("rules path emits .frs_rules_to_sql output", {
  sp <- sp_with_rules(rules = list(
    spawn = list(list(edge_types = c("stream", "canal")))))
  preds <- frs_habitat_predicates(sp)
  # Should emit edge-type IN clause from the rule, wrapped in (...)
  expect_match(preds$spawn, "edge_type IN \\(\\d+")
})

# -- Spawn predicate: CSV ranges fallback ------------------------------------

test_that("CSV ranges path uses spawn_gradient_min / max + channel_width", {
  sp <- sp_with_rules(rules = NULL)
  preds <- frs_habitat_predicates(sp)
  expect_match(preds$spawn, "s\\.gradient >= 0")
  expect_match(preds$spawn, "s\\.gradient <= 0\\.0549")
  expect_match(preds$spawn, "s\\.channel_width >= 2")
  expect_match(preds$spawn, "s\\.channel_width <= 9999")
})

test_that("CSV ranges path attaches edge_type filter when present", {
  sp <- sp_with_rules(rules = NULL)
  preds <- frs_habitat_predicates(sp)
  expect_match(preds$spawn, "s\\.edge_type IN \\(")
})

test_that("CSV ranges path with no edge_types emits no edge filter", {
  sp <- sp_with_rules(rules = NULL)
  sp$params_sp$spawn_edge_types <- NA
  preds <- frs_habitat_predicates(sp)
  expect_no_match(preds$spawn, "edge_type")
})

# -- Rear predicate: rules path ----------------------------------------------

test_that("rear rules path uses rear gradient (min=0) for inheritance", {
  sp <- sp_with_rules(rules = list(
    rear = list(list(edge_types = c("stream", "canal")))))
  preds <- frs_habitat_predicates(sp)
  expect_match(preds$rear, "edge_type IN \\(")
})

# -- Rear predicate: CSV ranges fallback -------------------------------------

test_that("rear CSV path uses gradient max + channel_width + edge_type", {
  sp <- sp_with_rules(rules = NULL)
  preds <- frs_habitat_predicates(sp)
  expect_match(preds$rear, "s\\.gradient <= 0\\.0849")
  expect_match(preds$rear, "s\\.channel_width >= 1\\.5")
  expect_match(preds$rear, "s\\.edge_type IN \\(")
})

test_that("rear CSV path with no rear ranges returns FALSE", {
  sp <- sp_with_rules(rules = NULL)
  sp$params_sp$ranges$rear <- NULL
  preds <- frs_habitat_predicates(sp)
  expect_equal(preds$rear, "FALSE")
})

test_that("rear CSV path with edge_types only emits edge filter", {
  # Half-state: ranges$rear exists but no gradient or cw, only the
  # rear_edge_types CSV column. parts must end up with the edge
  # filter alone — not the "FALSE" default.
  sp <- sp_with_rules(rules = NULL)
  sp$params_sp$ranges$rear$gradient <- NULL
  sp$params_sp$ranges$rear$channel_width <- NULL
  preds <- frs_habitat_predicates(sp)
  expect_match(preds$rear, "s\\.edge_type IN \\(")
  expect_no_match(preds$rear, "gradient")
  expect_no_match(preds$rear, "channel_width")
})

# -- Rules path inheritance from csv_thresholds ------------------------------

test_that("rules path inherits csv_thresholds when rule omits gradient", {
  # The whole point of the rules-path threading: csv_thresholds_spawn
  # carries spawn_gradient_min..max so a rule with no explicit
  # `gradient` inherits the CSV bounds. Without this contract,
  # default-bundle rules YAML would lose its CSV-driven thresholds.
  sp <- sp_with_rules(
    spawn_grad_min = 0.005,
    spawn_grad_max = 0.05,
    rules = list(
      spawn = list(list(edge_types = c("stream", "canal"),
                        thresholds = TRUE))))
  preds <- frs_habitat_predicates(sp)
  expect_match(preds$spawn, "s\\.gradient")
  # Inherited spawn_grad_min and max should appear in the SQL
  expect_match(preds$spawn, "0\\.005")
  expect_match(preds$spawn, "0\\.05")
})

test_that("rules path inherits csv channel_width when rule omits it", {
  sp <- sp_with_rules(
    spawn_cw = c(2, 9999),
    rules = list(
      spawn = list(list(edge_types = c("stream", "canal"),
                        thresholds = TRUE))))
  preds <- frs_habitat_predicates(sp)
  expect_match(preds$spawn, "s\\.channel_width")
  expect_match(preds$spawn, "2")
  expect_match(preds$spawn, "9999")
})

# -- Lake / wetland rear predicates: gated on waterbody_type rule ------------

test_that("no waterbody_type rule -> lake_rear and wetland_rear are FALSE", {
  sp <- sp_with_rules(rules = list(
    rear = list(list(edge_types = c("stream", "canal")))))
  preds <- frs_habitat_predicates(sp)
  expect_equal(preds$lake_rear, "FALSE")
  expect_equal(preds$wetland_rear, "FALSE")
})

test_that("waterbody_type: L without lake_ha_min -> join with no WHERE filter", {
  sp <- sp_with_rules(rules = list(
    rear = list(list(waterbody_type = "L"))))
  preds <- frs_habitat_predicates(sp)
  expect_match(preds$lake_rear, "fwa_lakes_poly\\)")
  expect_no_match(preds$lake_rear, "area_ha")
})

test_that("waterbody_type: L with lake_ha_min adds area_ha threshold", {
  sp <- sp_with_rules(rules = list(
    rear = list(list(waterbody_type = "L", lake_ha_min = 200))))
  preds <- frs_habitat_predicates(sp)
  expect_match(preds$lake_rear, "fwa_lakes_poly WHERE area_ha >= 200")
})

test_that("waterbody_type: W with wetland_ha_min adds area_ha threshold", {
  sp <- sp_with_rules(rules = list(
    rear = list(list(waterbody_type = "W", wetland_ha_min = 1.5))))
  preds <- frs_habitat_predicates(sp)
  expect_match(preds$wetland_rear, "fwa_wetlands_poly WHERE area_ha >= 1\\.5")
})

test_that("waterbody_type: L without rear channel_width -> FALSE (cw window required)", {
  sp <- sp_with_rules(rules = list(
    rear = list(list(waterbody_type = "L", lake_ha_min = 200))))
  sp$params_sp$ranges$rear$channel_width <- NULL
  preds <- frs_habitat_predicates(sp)
  expect_equal(preds$lake_rear, "FALSE")
})

test_that("rear rules with both L and stream rules emit lake_rear from L rule only", {
  sp <- sp_with_rules(rules = list(
    rear = list(
      list(edge_types = c("stream", "canal")),
      list(waterbody_type = "L", lake_ha_min = 100))))
  preds <- frs_habitat_predicates(sp)
  expect_match(preds$lake_rear, "fwa_lakes_poly WHERE area_ha >= 100")
  # rear_pred (overall rearing) is the OR of all rules
  expect_match(preds$rear, "edge_type IN \\(")
})

# -- Argument validation -----------------------------------------------------

test_that("rejects non-list sp_params", {
  expect_error(frs_habitat_predicates("not a list"), "is.list")
})

test_that("rejects sp_params missing species_code", {
  expect_error(frs_habitat_predicates(list(other = 1)),
               "species_code")
})

test_that("rejects sp_params missing params_sp", {
  expect_error(frs_habitat_predicates(list(species_code = "CO")),
               "params_sp")
})

# -- Return shape ------------------------------------------------------------

test_that("returns named list with exactly 4 character predicates", {
  sp <- sp_with_rules(rules = NULL)
  preds <- frs_habitat_predicates(sp)
  expect_named(preds, c("spawn", "rear", "lake_rear", "wetland_rear"))
  for (p in preds) {
    expect_type(p, "character")
    expect_length(p, 1)
  }
})
