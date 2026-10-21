# Unit tests: the near_river rule condition (#259), loader and compiler.
# Pure R, no DB.

write_rules <- function(lines) {
  tmp <- tempfile(fileext = ".yaml")
  writeLines(lines, tmp)
  tmp
}

nr_rule_yaml <- function(extra = c("        discharge_min: 3",
                                   "        distance_max: 1000"),
                         head = c("CH:", "  rear:",
                                  "    - edge_types_explicit: [1000, 1100]",
                                  "      near_river:")) {
  write_rules(c(head, extra))
}

nr_tbl <- "w.streams_near_river"
nr_exists <- paste0(
  "EXISTS (SELECT 1 FROM w.streams_near_river n WHERE n.id_segment = s.id_segment ",
  "AND n.watershed_group_code = s.watershed_group_code ",
  "AND n.discharge_min = 3 AND n.distance_max = 1000 AND n.dist_m <= 1000)")

# -- loader ----------------------------------------------------------------

test_that(".frs_load_rules accepts near_river and stores numerics", {
  tmp <- nr_rule_yaml()
  on.exit(unlink(tmp))
  expect_silent(rules <- .frs_load_rules(tmp))
  nr <- rules$CH$rear[[1]]$near_river
  expect_identical(names(nr), c("discharge_min", "distance_max"))
  expect_type(nr$discharge_min, "double")
  expect_type(nr$distance_max, "double")
  expect_equal(nr$discharge_min, 3)
  expect_equal(nr$distance_max, 1000)
})

test_that(".frs_load_rules accepts near_river on spawn and on a river rule", {
  tmp <- write_rules(c(
    "CH:", "  spawn:", "    - waterbody_type: R", "      near_river:",
    "        distance_max: 500.5", "        discharge_min: 0.5"))
  on.exit(unlink(tmp))
  rules <- .frs_load_rules(tmp)
  expect_equal(rules$CH$spawn[[1]]$near_river,
               list(discharge_min = 0.5, distance_max = 500.5))
})

test_that(".frs_load_rules rejects malformed near_river", {
  bad <- list(
    empty = character(0),
    scalar = NULL,
    unknown = c("        discharge_min: 3", "        distance_max: 1000",
                "        upstream: true"),
    missing_d = "        discharge_min: 3",
    missing_q = "        distance_max: 1000",
    zero_q = c("        discharge_min: 0", "        distance_max: 1000"),
    neg_d = c("        discharge_min: 3", "        distance_max: -1"),
    inf_d = c("        discharge_min: 3", "        distance_max: .inf"),
    text_q = c("        discharge_min: three", "        distance_max: 1000"),
    vec_q = c("        discharge_min: [3, 4]", "        distance_max: 1000"),
    bool_d = c("        discharge_min: 3", "        distance_max: true")
  )
  msgs <- c(empty = "named mapping", scalar = "named mapping",
            unknown = "unknown keys: upstream",
            missing_d = "missing: distance_max",
            missing_q = "missing: discharge_min",
            zero_q = "discharge_min must be a finite number above zero",
            neg_d = "distance_max must be a finite number above zero",
            inf_d = "distance_max must be a finite number above zero",
            text_q = "discharge_min must be a finite number above zero",
            vec_q = "discharge_min must be a finite number above zero",
            bool_d = "distance_max must be a finite number above zero")
  for (k in names(bad)) {
    tmp <- if (k == "scalar") {
      write_rules(c("CH:", "  rear:", "    - edge_types_explicit: [1000]",
                    "      near_river: 3"))
    } else {
      nr_rule_yaml(extra = bad[[k]])
    }
    expect_error(.frs_load_rules(tmp), msgs[[k]], info = k)
    expect_error(.frs_load_rules(tmp), "CH/rear rule 1 near_river", info = k)
    unlink(tmp)
  }
})

test_that(".frs_load_rules refuses near_river on lake and wetland rules", {
  for (wt in c("L", "W")) {
    tmp <- write_rules(c(
      "CH:", "  rear:", sprintf("    - waterbody_type: %s", wt),
      "      near_river:", "        discharge_min: 3",
      "        distance_max: 1000"))
    expect_error(.frs_load_rules(tmp),
                 sprintf("not allowed on a waterbody_type: %s rule", wt))
    unlink(tmp)
  }
})

# -- compiler --------------------------------------------------------------

nr <- list(discharge_min = 3, distance_max = 1000)

test_that("near_river ORs the inherited channel width with the EXISTS", {
  rule <- list(edge_types_explicit = c(1000, 1100), near_river = nr)
  sql <- .frs_rule_to_sql(rule,
    list(gradient = c(0, 0.05), channel_width = c(4, 9999)),
    near_river_table = nr_tbl)
  expect_identical(sql, paste0(
    "(s.edge_type IN (1000, 1100) AND s.gradient BETWEEN 0 AND 0.05 AND ",
    "(s.channel_width BETWEEN 4 AND 9999 OR ", nr_exists, "))"))
})

test_that("near_river groups channel width AND mad before the OR", {
  rule <- list(channel_width = c(2, 9999), mad = c(0.5, 100),
               near_river = nr)
  sql <- .frs_rule_to_sql(rule, list(gradient = c(0, 0.05)),
                          near_river_table = nr_tbl)
  expect_identical(sql, paste0(
    "(s.gradient BETWEEN 0 AND 0.05 AND ",
    "(s.channel_width BETWEEN 2 AND 9999 AND s.mad_m3s BETWEEN 0.5 AND 100 OR ",
    nr_exists, "))"))
})

test_that("near_river rescues a mad species with no MAD range", {
  rule <- list(edge_types_explicit = 1000, near_river = nr)
  sql <- .frs_rule_to_sql(rule,
    list(gradient = c(0, 0.05), mad_m3s = c(NA_real_, NA_real_)),
    near_river_table = nr_tbl)
  expect_identical(sql, paste0(
    "(s.edge_type IN (1000) AND s.gradient BETWEEN 0 AND 0.05 AND ",
    "(FALSE OR ", nr_exists, "))"))
})

test_that("near_river with no size part is the rule's only size test", {
  rule <- list(edge_types_explicit = 1000, gradient = c(0, 0.05),
               thresholds = FALSE, near_river = nr)
  sql <- .frs_rule_to_sql(rule, list(gradient = c(0, 0.1),
                                     channel_width = c(4, 9999)),
                          near_river_table = nr_tbl)
  expect_identical(sql, paste0(
    "(s.edge_type IN (1000) AND s.gradient BETWEEN 0 AND 0.05 AND ",
    nr_exists, ")"))
})

test_that("thresholds: false + near_river carries no gradient test", {
  # Pinned on purpose (#259 open item b): a `thresholds: false` rule
  # inherits no gradient, so it needs its own `gradient:` to test slope.
  rule <- list(edge_types_explicit = c(1050, 1150), thresholds = FALSE,
               near_river = nr)
  sql <- .frs_rule_to_sql(rule, list(gradient = c(0, 0.05),
                                     channel_width = c(4, 9999)),
                          near_river_table = nr_tbl)
  expect_identical(sql, paste0("(s.edge_type IN (1050, 1150) AND ",
                               nr_exists, ")"))
  expect_false(grepl("gradient", sql))
})

test_that("the EXISTS never reads s.mad_m3s or s.channel_width", {
  sql <- .frs_near_river_sql(nr, nr_tbl)
  expect_false(grepl("s\\.mad_m3s|s\\.channel_width", sql))
  expect_identical(sql, nr_exists)
})

test_that("near_river without a table errors, naming the argument", {
  rule <- list(edge_types_explicit = 1000, near_river = nr)
  expect_error(.frs_rule_to_sql(rule, list(channel_width = c(4, 9999))),
               "near_river_table is NULL.*frs_habitat_classify")
  expect_error(.frs_rule_to_sql(rule, near_river_table = "x; DROP"),
               "near_river_table contains invalid characters")
})

test_that("rules without near_river compile byte-identically", {
  csv <- list(gradient = c(0, 0.05), channel_width = c(4, 9999),
              mad_m3s = c(0.5, 100))
  rules <- list(
    list(edge_types_explicit = c(1000, 1100)),
    list(channel_width = c(0, 9999), mad = c(1, 2)),
    list(edge_types_explicit = c(1050, 1150), thresholds = FALSE),
    list(waterbody_type = "R", channel_width = c(0, 9999)))
  for (r in rules) {
    a <- .frs_rule_to_sql(r, csv)
    b <- .frs_rule_to_sql(r, csv, near_river_table = nr_tbl)
    expect_identical(a, b)
    expect_false(grepl("EXISTS|OR", a))
  }
  expect_identical(
    .frs_rule_to_sql(rules[[2]], csv),
    paste0("(s.gradient BETWEEN 0 AND 0.05 AND s.channel_width BETWEEN 0 AND ",
           "9999 AND s.mad_m3s BETWEEN 1 AND 2)"))
})

test_that(".frs_rules_to_sql threads near_river_table to every rule", {
  rules <- list(list(edge_types_explicit = 1000, near_river = nr),
                list(edge_types_explicit = 2000,
                     near_river = list(discharge_min = 10, distance_max = 50)))
  sql <- .frs_rules_to_sql(rules, list(channel_width = c(4, 9999)),
                           near_river_table = nr_tbl)
  expect_match(sql, "n.discharge_min = 3 AND n.distance_max = 1000 AND n.dist_m <= 1000",
               fixed = TRUE)
  expect_match(sql, "n.discharge_min = 10 AND n.distance_max = 50 AND n.dist_m <= 50",
               fixed = TRUE)
})

# -- frs_habitat_predicates and the spec collector -------------------------

sp_nr <- function(rules, rear_mad = NULL) {
  sp <- list(species_code = "CH", spawn_gradient_min = 0,
             spawn_gradient_max = 0.0449,
             params_sp = list(
               ranges = list(
                 spawn = list(channel_width = c(4, 9999),
                              gradient = c(0, 0.0449)),
                 rear = list(channel_width = c(1.5, 9999),
                             gradient = c(0, 0.0549))),
               rules = rules))
  sp$params_sp$ranges$rear$mad_m3s <- rear_mad
  sp
}

test_that("frs_habitat_predicates threads the table to spawn and rear", {
  rules <- list(spawn = list(list(edge_types_explicit = 1000, near_river = nr)),
                rear = list(list(edge_types_explicit = 1000, near_river = nr)))
  preds <- frs_habitat_predicates(sp_nr(rules), near_river_table = nr_tbl)
  expect_match(preds$spawn, "(s.channel_width BETWEEN 4 AND 9999 OR EXISTS",
               fixed = TRUE)
  expect_match(preds$rear, "(s.channel_width BETWEEN 1.5 AND 9999 OR EXISTS",
               fixed = TRUE)
  expect_error(frs_habitat_predicates(sp_nr(rules)), "near_river_table")
})

test_that("under mad, near_river keeps a mad range or rescues a missing one", {
  rules <- list(rear = list(list(edge_types_explicit = 1000, near_river = nr)))
  with_range <- frs_habitat_predicates(sp_nr(rules, rear_mad = c(0.28, 100)),
                                       model = "mad", near_river_table = nr_tbl)
  expect_match(with_range$rear, "(s.mad_m3s BETWEEN 0.28 AND 100 OR EXISTS",
               fixed = TRUE)
  no_range <- frs_habitat_predicates(sp_nr(rules), model = "mad",
                                     near_river_table = nr_tbl)
  expect_match(no_range$rear, "(FALSE OR EXISTS", fixed = TRUE)
  # A river rule's channel_width is stripped under mad; with
  # thresholds: false nothing is left, so near_river stands alone.
  rules_r <- list(rear = list(list(waterbody_type = "R",
                                   channel_width = c(0, 9999),
                                   thresholds = FALSE, near_river = nr)))
  r_mad <- frs_habitat_predicates(sp_nr(rules_r), model = "mad",
                                  near_river_table = nr_tbl)
  expect_false(grepl("channel_width|mad_m3s|OR", r_mad$rear))
  expect_match(r_mad$rear, "EXISTS", fixed = TRUE)
})

test_that("species without near_river build no EXISTS and need no table", {
  rules <- list(rear = list(list(edge_types_explicit = 1000)))
  expect_false(grepl("EXISTS", frs_habitat_predicates(sp_nr(rules))$rear))
})

test_that(".frs_near_river_specs lists each distinct pair once", {
  params <- list(
    CH = list(rules = list(
      spawn = list(list(near_river = list(discharge_min = 3, distance_max = 500))),
      rear = list(list(near_river = list(discharge_min = 3, distance_max = 1000)),
                  list(edge_types_explicit = 1000)))),
    CO = list(rules = list(
      rear = list(list(near_river = list(discharge_min = 1, distance_max = 200))))),
    BT = list(rules = list(
      rear = list(list(near_river = list(discharge_min = 10, distance_max = 9e3))))))
  specs <- .frs_near_river_specs(params, c("CH", "CO"))
  expect_identical(specs, data.frame(discharge_min = c(1, 3, 3),
                                     distance_max = c(200, 500, 1000)))
  # A pair two rules share is walked once.
  params$CO$rules$spawn <- list(list(near_river = list(discharge_min = 1,
                                                       distance_max = 200)))
  expect_identical(nrow(.frs_near_river_specs(params, c("CH", "CO"))), 3L)
  none <- .frs_near_river_specs(params["CO"], "BT")
  expect_identical(nrow(none), 0L)
  expect_identical(names(none), c("discharge_min", "distance_max"))
})
