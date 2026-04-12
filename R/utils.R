# Internal helpers — not exported

#' Get a configurable column name from options
#'
#' Reads `options(fresh.<name>)` with a default for FWA naming.
#' This is the foundation for #44 (configurable column names for
#' spyda compatibility). Set options once per session:
#'
#' ```
#' options(fresh.wscode_col = "wscode",
#'         fresh.localcode_col = "localcode")
#' ```
#'
#' @param name Character. Option suffix (e.g. `"wscode_col"`).
#' @return Character scalar.
#' @noRd
.frs_opt <- function(name) {
  defaults <- list(
    tbl_network = "whse_basemapping.fwa_stream_networks_sp",
    wscode_col = "wscode_ltree",
    localcode_col = "localcode_ltree",
    blk_col = "blue_line_key",
    measure_ds_col = "downstream_route_measure",
    measure_us_col = "upstream_route_measure",
    segment_id_col = "linear_feature_id"
  )
  getOption(paste0("fresh.", name), default = defaults[[name]])
}

#' Quote a string value for safe SQL interpolation
#'
#' Escapes single quotes by doubling them (SQL standard) and wraps in single
#' quotes. Prevents SQL injection for string literals without needing a DB
#' connection.
#'
#' @param x Character scalar.
#' @return Character scalar, e.g. `"'O''Brien'"`.
#' @noRd
.frs_quote_string <- function(x) {
  paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
}


#' Validate a SQL identifier (table or column name)
#'
#' Checks that the identifier matches a safe pattern: word characters, dots
#' (for schema-qualified names), and underscores. Stops with an informative
#' error if validation fails.
#'
#' @param x Character scalar.
#' @param label Character. Name used in error message (e.g. `"table"`).
#' @return `x` invisibly (called for side effect).
#' @noRd
.frs_validate_identifier <- function(x, label = "identifier") {
  if (identical(x, "*")) return(invisible(x))
  if (!grepl("^[A-Za-z_][A-Za-z0-9_.]*$", x)) {
    stop(sprintf("%s contains invalid characters: %s", label, x), call. = FALSE)
  }
  invisible(x)
}


#' Format a numeric value as a locale-safe SQL literal
#'
#' Uses `sprintf` which is not affected by `options(OutDec)`,
#' unlike `format()` or `formatC()`.
#'
#' @param x Numeric scalar.
#' @return Character string safe for SQL interpolation.
#' @noRd
.frs_sql_num <- function(x) {
  sprintf("%.10g", x)
}


#' Format a gradient threshold as a `gradient_NNNN` label
#'
#' Generates the canonical 4-digit zero-padded basis-point label.
#' `0.05` becomes `"gradient_0500"`. `0.0549` becomes
#' `"gradient_0549"`.
#'
#' @param thr Numeric scalar in `[0, 1]`. Caller should validate
#'   first via [.frs_validate_gradient_thresholds()].
#' @return Character scalar.
#' @noRd
.frs_gradient_label <- function(thr) {
  sprintf("gradient_%04d", as.integer(round(thr * 10000)))
}


#' Validate a vector of gradient threshold values
#'
#' Errors if any value is:
#'   - not numeric or NA
#'   - outside `[0, 1]` (gradient is a fraction, not a percent)
#'   - cannot be represented exactly at basis-point precision
#'     (e.g. `0.05001` rounds to the same label as `0.05`)
#'   - duplicates another value's label after rounding
#'
#' Catches the silent failure mode where two distinct user-supplied
#' thresholds produce the same `gradient_NNNN` label and would
#' overwrite each other's barrier table.
#'
#' @param x Numeric vector of gradient thresholds (as fractions).
#' @param name Character. Argument name for error messages.
#' @return Invisible `x`. Errors on failure.
#' @noRd
.frs_validate_gradient_thresholds <- function(x, name = "thresholds") {
  if (!is.numeric(x)) {
    stop(sprintf("%s must be numeric", name), call. = FALSE)
  }
  if (length(x) == 0) {
    return(invisible(x))
  }
  if (any(is.na(x))) {
    stop(sprintf("%s contains NA values", name), call. = FALSE)
  }
  if (any(x < 0 | x > 1)) {
    bad <- x[x < 0 | x > 1]
    stop(sprintf(
      "%s values must be in [0, 1] (gradient as fraction, not percent). Got: %s",
      name, paste(bad, collapse = ", ")
    ), call. = FALSE)
  }

  # Precision check: must round-trip through 4-digit basis points
  rounded <- as.integer(round(x * 10000)) / 10000
  diffs <- abs(x - rounded)
  if (any(diffs > 1e-10)) {
    bad <- x[diffs > 1e-10]
    stop(sprintf(
      paste0(
        "%s values exceed basis-point precision (0.0001). ",
        "Each value must be representable as gradient_NNNN. Got: %s. ",
        "Round to 4 decimal places (e.g. 0.0549)."
      ),
      name, paste(bad, collapse = ", ")
    ), call. = FALSE)
  }

  # Label collision check: after rounding, no two values should map
  # to the same label. This is a defensive check — should be impossible
  # if precision check passed.
  labels_int <- as.integer(round(x * 10000))
  if (anyDuplicated(labels_int)) {
    dup_idx <- duplicated(labels_int) | duplicated(labels_int, fromLast = TRUE)
    bad <- unique(x[dup_idx])
    stop(sprintf(
      "%s values produce duplicate labels at basis-point precision: %s",
      name, paste(bad, collapse = ", ")
    ), call. = FALSE)
  }

  invisible(x)
}


#' Convert a single rule to a SQL AND predicate
#'
#' Translates one habitat rule (a list of predicates) into a
#' parenthesized SQL string joining the predicates with AND. When
#' `rule$thresholds` is `TRUE` (default) or unset, the species'
#' CSV-derived gradient/channel_width thresholds from `csv_thresholds`
#' are added to the AND chain. When `FALSE`, the rule stands alone
#' (the wetland-flow carve-out pattern).
#'
#' @param rule Named list with optional fields: `edge_types`,
#'   `edge_types_explicit`, `waterbody_type`, `lake_ha_min`,
#'   `thresholds`.
#' @param csv_thresholds Named list with `gradient = c(min, max)`
#'   and/or `channel_width = c(min, max)`. Either may be NULL.
#' @return Character. A parenthesized SQL predicate.
#'   Returns `"(TRUE)"` if the rule has no predicates and no
#'   thresholds to inherit (a wide-open rule).
#' @noRd
.frs_rule_to_sql <- function(rule, csv_thresholds = NULL) {
  parts <- character(0)

  # Use [[ ]] not $ to avoid partial matching: rule$edge_types
  # would match rule$edge_types_explicit because edge_types is a
  # prefix.
  inherit_thresholds <- is.null(rule[["thresholds"]]) ||
    isTRUE(rule[["thresholds"]])

  # Auto-skip gradient/cw inheritance for lake/wetland rules.
  # Lake and wetland flow lines are routing lines through waterbodies —
  # gradient and channel_width are meaningless on them. The relevant
  # threshold is lake_ha_min, not stream channel dimensions.
  # Rule-level explicit overrides (rule[["gradient"]], rule[["channel_width"]])
  # still apply if someone sets them deliberately.
  wb_type <- rule[["waterbody_type"]]
  if (!is.null(wb_type) && wb_type %in% c("L", "W")) {
    inherit_thresholds <- FALSE
  }

  if (!is.null(rule[["edge_types"]])) {
    et_categories <- rule[["edge_types"]]
    codes <- unlist(lapply(et_categories, function(et_category) {
      frs_edge_types(category = et_category)$edge_type
    }))
    if (length(codes) > 0) {
      parts <- c(parts, sprintf("s.edge_type IN (%s)",
        paste(codes, collapse = ", ")))
    }
  }

  if (!is.null(rule[["edge_types_explicit"]])) {
    codes <- as.integer(rule[["edge_types_explicit"]])
    parts <- c(parts, sprintf("s.edge_type IN (%s)",
      paste(codes, collapse = ", ")))
  }

  if (!is.null(rule[["waterbody_type"]])) {
    wb_table <- switch(rule[["waterbody_type"]],
      "L" = "whse_basemapping.fwa_lakes_poly",
      "R" = "whse_basemapping.fwa_rivers_poly",
      "W" = "whse_basemapping.fwa_wetlands_poly")
    if (!is.null(rule[["lake_ha_min"]])) {
      # Already validated as L by parser
      parts <- c(parts, sprintf(
        "s.waterbody_key IN (SELECT waterbody_key FROM %s WHERE area_ha >= %s)",
        wb_table, .frs_sql_num(rule[["lake_ha_min"]])))
    } else {
      parts <- c(parts, sprintf(
        "s.waterbody_key IN (SELECT waterbody_key FROM %s)",
        wb_table))
    }
  }

  # Gradient: rule-level override wins, then CSV inheritance fills gap.
  # A rule with gradient: [0, 9999] explicitly overrides the CSV value.
  # A rule without gradient inherits from CSV when thresholds: true.
  if (!is.null(rule[["gradient"]])) {
    g <- rule[["gradient"]]
    parts <- c(parts, sprintf(
      "s.gradient BETWEEN %s AND %s",
      .frs_sql_num(g[1]), .frs_sql_num(g[2])))
  } else if (inherit_thresholds && !is.null(csv_thresholds) &&
             !is.null(csv_thresholds$gradient)) {
    g <- csv_thresholds$gradient
    parts <- c(parts, sprintf(
      "s.gradient BETWEEN %s AND %s",
      .frs_sql_num(g[1]), .frs_sql_num(g[2])))
  }

  # Channel width: same override-then-inherit pattern.
  if (!is.null(rule[["channel_width"]])) {
    cw <- rule[["channel_width"]]
    parts <- c(parts, sprintf(
      "s.channel_width BETWEEN %s AND %s",
      .frs_sql_num(cw[1]), .frs_sql_num(cw[2])))
  } else if (inherit_thresholds && !is.null(csv_thresholds) &&
             !is.null(csv_thresholds$channel_width)) {
    cw <- csv_thresholds$channel_width
    parts <- c(parts, sprintf(
      "s.channel_width BETWEEN %s AND %s",
      .frs_sql_num(cw[1]), .frs_sql_num(cw[2])))
  }

  if (length(parts) == 0) return("(TRUE)")
  paste0("(", paste(parts, collapse = " AND "), ")")
}


#' Convert a list of rules to a SQL OR predicate
#'
#' Joins individual rule SQL predicates with OR and parenthesizes the
#' result. An empty rule list returns `"FALSE"` (no segments qualify).
#'
#' @param rules List of rule lists. Empty list → `"FALSE"`.
#' @param csv_thresholds Same as for [.frs_rule_to_sql()].
#' @return Character. A parenthesized SQL predicate, or `"FALSE"`.
#' @noRd
.frs_rules_to_sql <- function(rules, csv_thresholds = NULL) {
  if (is.null(rules) || length(rules) == 0) {
    return("FALSE")
  }
  rule_sqls <- vapply(rules, .frs_rule_to_sql, character(1),
                      csv_thresholds = csv_thresholds)
  paste0("(", paste(rule_sqls, collapse = " OR "), ")")
}


#' Add id_segment column to a working table
#'
#' Assigns a unique integer ID to every row. Uses `linear_feature_id`
#' as the starting value (so original FWA segments keep their ID),
#' then generates new IDs for any rows added later by
#' [frs_break_apply()].
#'
#' @param conn DBI connection.
#' @param table Schema-qualified table name.
#' @noRd
.frs_add_id_segment <- function(conn, table) {
  if (!inherits(conn, "DBIConnection")) return(invisible(NULL))
  .frs_db_execute(conn, sprintf(
    "ALTER TABLE %s ADD COLUMN IF NOT EXISTS id_segment integer", table))
  .frs_db_execute(conn, sprintf(
    "UPDATE %s SET id_segment = linear_feature_id
     WHERE id_segment IS NULL", table))
}


#' Add indexes to a working table based on available columns
#'
#' Checks which index-worthy columns exist and creates appropriate indexes.
#' Runs ANALYZE after indexing for up-to-date statistics.
#'
#' @param conn DBI connection.
#' @param table Schema-qualified table name.
#' @noRd
.frs_index_working <- function(conn, table) {
  .frs_validate_identifier(table, "table")

  # Skip indexing for non-DB connections (e.g. mock connections in tests)
  if (!inherits(conn, "DBIConnection")) return(invisible(NULL))

  # Get columns in this table
  parts <- strsplit(table, "\\.")[[1]]
  schema <- if (length(parts) == 2) parts[1] else "public"
  tbl <- parts[length(parts)]

  cols <- DBI::dbGetQuery(conn, sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = %s AND table_name = %s",
    .frs_quote_string(schema), .frs_quote_string(tbl)
  ))$column_name

  # Build index statements based on available columns
  idx <- character(0)

  if ("blue_line_key" %in% cols) {
    idx <- c(idx, sprintf("CREATE INDEX ON %s (blue_line_key)", table))
  }
  if (all(c("blue_line_key", "downstream_route_measure") %in% cols)) {
    idx <- c(idx, sprintf(
      "CREATE INDEX ON %s (blue_line_key, downstream_route_measure)", table))
  }
  if ("wscode_ltree" %in% cols) {
    idx <- c(idx, sprintf(
      "CREATE INDEX ON %s USING gist (wscode_ltree)", table))
    idx <- c(idx, sprintf(
      "CREATE INDEX ON %s USING btree (wscode_ltree)", table))
  }
  if ("localcode_ltree" %in% cols) {
    idx <- c(idx, sprintf(
      "CREATE INDEX ON %s USING gist (localcode_ltree)", table))
    idx <- c(idx, sprintf(
      "CREATE INDEX ON %s USING btree (localcode_ltree)", table))
  }
  if ("linear_feature_id" %in% cols) {
    idx <- c(idx, sprintf("CREATE INDEX ON %s (linear_feature_id)", table))
  }
  if ("watershed_group_code" %in% cols) {
    idx <- c(idx, sprintf("CREATE INDEX ON %s (watershed_group_code)", table))
  }
  if ("label" %in% cols) {
    idx <- c(idx, sprintf("CREATE INDEX ON %s (label)", table))
    if ("blue_line_key" %in% cols) {
      idx <- c(idx, sprintf("CREATE INDEX ON %s (label, blue_line_key)", table))
    }
  }
  if ("id_segment" %in% cols) {
    idx <- c(idx, sprintf("CREATE INDEX ON %s (id_segment)", table))
  }
  if ("species_code" %in% cols) {
    idx <- c(idx, sprintf("CREATE INDEX ON %s (species_code)", table))
  }

  for (sql in idx) {
    .frs_db_execute(conn, sql)
  }

  .frs_db_execute(conn, sprintf("ANALYZE %s", table))
}


#' Build a SQL WHERE clause from common filter parameters
#'
#' @param watershed_group_code Character or NULL.
#' @param blue_line_key Integer or NULL.
#' @param bbox Numeric length-4 or NULL (xmin, ymin, xmax, ymax in EPSG:3005).
#' @param extra Character vector of additional SQL predicates.
#'
#' @return Character string starting with " WHERE ..." or empty string.
#' @noRd
.frs_build_where <- function(
    watershed_group_code = NULL,
    blue_line_key = NULL,
    bbox = NULL,
    extra = NULL
) {
  clauses <- character(0)

  if (!is.null(watershed_group_code)) {
    clauses <- c(
      clauses,
      paste0("watershed_group_code = ", .frs_quote_string(watershed_group_code))
    )
  }

  if (!is.null(blue_line_key)) {
    clauses <- c(clauses, paste0("blue_line_key = ", as.integer(blue_line_key)))
  }

  if (!is.null(bbox)) {
    stopifnot(length(bbox) == 4)
    clauses <- c(
      clauses,
      sprintf(
        "geom && ST_MakeEnvelope(%s, %s, %s, %s, 3005)",
        bbox[1], bbox[2], bbox[3], bbox[4]
      )
    )
  }

  if (!is.null(extra)) {
    clauses <- c(clauses, extra)
  }

  if (length(clauses) == 0) return("")

  paste0(" WHERE ", paste(clauses, collapse = " AND "))
}


#' Stream filtering guards to exclude invalid FWA segments
#'
#' Returns SQL predicates that filter out placeholder streams (999 wscode)
#' and unmapped tributaries (NULL localcode). These are no-ops in network
#' traversal (fwa_upstream/fwa_downstream never return them) but matter
#' for direct table queries (frs_stream_fetch, frs_point_snap KNN).
#'
#' Subsurface flow (edge_type 1425 — underground conduits) and network
#' connectors (edge_type 1410 — wetland connectivity) are NOT filtered by
#' default because these are real network connectivity. Use
#' [.frs_snap_guards()] for snap-specific filtering that excludes
#' subsurface segments (1425 only by default).
#'
#' @param alias Character. Table alias prefix. Default `"s"`.
#' @param wscode_col Character. Watershed code column name. Default
#'   `"wscode_ltree"`.
#' @param localcode_col Character. Local code column name. Default
#'   `"localcode_ltree"`.
#' @return Character vector of SQL predicates.
#' @noRd
.frs_stream_guards <- function(alias = "s", wscode_col = "wscode_ltree",
                               localcode_col = "localcode_ltree") {
  prefix <- if (nzchar(alias)) paste0(alias, ".") else ""
  c(
    paste0(prefix, localcode_col, " IS NOT NULL"),
    paste0("NOT ", prefix, wscode_col, " <@ '999'")
  )
}


#' Snap-specific filtering guards
#'
#' Like [.frs_stream_guards()] but also excludes subsurface flow
#' (edge_type 1425 — underground conduits). Used by the KNN snap
#' path where snapping to a culvert is not useful.
#'
#' Note: edge_type 1410 (network connector) is NOT excluded — these are
#' real wetland connectivity (204K segments in wetlands). See
#' NewGraphEnvironment/bcfishpass#8 for discussion.
#'
#' @inheritParams .frs_stream_guards
#' @param exclude_edge_types Integer vector or `NULL`. Edge types to exclude
#'   from snap candidates. Default `1425` (subsurface flow). Set to `NULL`
#'   to snap to all edge types.
#' @return Character vector of SQL predicates.
#' @noRd
.frs_snap_guards <- function(alias = "s", wscode_col = "wscode_ltree",
                             localcode_col = "localcode_ltree",
                             exclude_edge_types = 1425L) {
  guards <- .frs_stream_guards(alias, wscode_col, localcode_col)

  if (!is.null(exclude_edge_types) && length(exclude_edge_types) > 0) {
    prefix <- if (nzchar(alias)) paste0(alias, ".") else ""
    codes <- paste(as.integer(exclude_edge_types), collapse = ", ")
    guards <- c(guards, paste0(prefix, "edge_type NOT IN (", codes, ")"))
  }

  guards
}


#' Check if table is the FWA base stream network table
#' @noRd
.is_fwa_stream_table <- function(table) {
  grepl("fwa_stream_networks_sp", tolower(table))
}


#' Check if a DB connection to fwapg is available
#'
#' Attempts to connect and run a trivial query. Returns `TRUE` on success,
#' `FALSE` on any failure. Used by integration tests to skip gracefully
#' when no tunnel/DB is available.
#'
#' @return Logical scalar.
#' @noRd
.frs_db_available <- function() {
  tryCatch({
    conn <- frs_db_conn()
    on.exit(DBI::dbDisconnect(conn))
    DBI::dbGetQuery(conn, "SELECT 1")
    TRUE
  }, error = function(e) FALSE)
}


#' Resolve an AOI specification to a SQL WHERE predicate
#'
#' Normalizes any AOI input into a SQL predicate string that can be appended
#' to a WHERE clause. Handles sf polygons, table+id lookups, character
#' shortcuts (via partition options), blk+measure watershed delineation,
#' and NULL (no filter).
#'
#' @param aoi AOI specification. One of:
#'   - `NULL` — no spatial filter
#'   - Character vector — shortcut for partition table lookup using
#'     `getOption("fresh.partition_table")` and
#'     `getOption("fresh.partition_col")`
#'   - `sf`/`sfc` polygon — spatial intersection
#'   - Named list with `table` and `id` (and optionally `id_col`) — lookup
#'     polygon from a pg table
#'   - Named list with `blk` and `measure` — delineate watershed via
#'     `fwa_watershedatmeasure()`
#' @param conn A [DBI::DBIConnection-class] object. Required for sf upload,
#'   table lookup, and blk+measure delineation. Not needed for character
#'   or NULL inputs.
#' @param geom_col Character. Name of the geometry column in the target
#'   table. Default `"geom"`.
#' @param alias Character. Table alias prefix for the predicate. Default
#'   `""` (no prefix).
#'
#' @return Character scalar. A SQL predicate (without leading WHERE/AND),
#'   or empty string `""` for NULL aoi.
#' @noRd
.frs_resolve_aoi <- function(aoi, conn = NULL, geom_col = "geom",
                             alias = "") {
  if (is.null(aoi)) return("")

  prefix <- if (nzchar(alias)) paste0(alias, ".") else ""

  # Character vector — partition table shortcut

  if (is.character(aoi)) {
    tbl <- getOption("fresh.partition_table",
                     "whse_basemapping.fwa_watershed_groups_poly")
    col <- getOption("fresh.partition_col", "watershed_group_code")
    .frs_validate_identifier(tbl, "partition table")
    .frs_validate_identifier(col, "partition column")
    quoted <- paste(vapply(aoi, .frs_quote_string, character(1)),
                    collapse = ", ")
    return(sprintf(
      "%s%s && (SELECT ST_Union(geom) FROM %s WHERE %s IN (%s))",
      prefix, geom_col, tbl, col, quoted
    ))
  }

  # sf/sfc polygon — spatial intersection
  if (inherits(aoi, c("sf", "sfc"))) {
    # Transform to BC Albers (3005) to match DB geometry
    aoi_3005 <- sf::st_transform(aoi, 3005)
    wkt <- sf::st_as_text(sf::st_union(sf::st_geometry(aoi_3005)))
    return(sprintf(
      "ST_Intersects(%s%s, ST_GeomFromText('%s', 3005))",
      prefix, geom_col, wkt
    ))
  }

  # Named list — table+id lookup or blk+measure delineation
  if (is.list(aoi)) {
    # blk + measure → watershed delineation
    if (!is.null(aoi$blk) && !is.null(aoi$measure)) {
      blk <- as.integer(aoi$blk)
      measure <- as.numeric(aoi$measure)
      return(sprintf(
        "ST_Intersects(%s%s, (SELECT ST_Union(geom) FROM whse_basemapping.fwa_watershedatmeasure(%d, %s)))",
        prefix, geom_col, blk, measure
      ))
    }

    # table + id → polygon lookup
    if (!is.null(aoi$table) && !is.null(aoi$id)) {
      .frs_validate_identifier(aoi$table, "AOI table")
      id_col <- if (!is.null(aoi$id_col)) aoi$id_col else "id"
      .frs_validate_identifier(id_col, "AOI id column")
      id_val <- if (is.character(aoi$id)) {
        .frs_quote_string(aoi$id)
      } else {
        as.character(aoi$id)
      }
      return(sprintf(
        "ST_Intersects(%s%s, (SELECT ST_Union(geom) FROM %s WHERE %s = %s))",
        prefix, geom_col, aoi$table, id_col, id_val
      ))
    }

    stop("list aoi must have 'blk'+'measure' or 'table'+'id'", call. = FALSE)
  }

  stop(
    sprintf("aoi must be NULL, character, sf, or list. Got: %s", class(aoi)[1]),
    call. = FALSE
  )
}


#' Execute a DDL/DML statement (CREATE, UPDATE, INSERT, DROP, ALTER)
#'
#' Complement to [frs_db_query()] which only handles SELECT via
#' [sf::st_read()]. This wraps [DBI::dbExecute()] for write operations.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param sql Character. SQL statement to execute.
#' @return The number of rows affected (invisibly).
#' @noRd
.frs_db_execute <- function(conn, sql) {
  DBI::dbExecute(conn, sql)
}


#' Get column names for a schema-qualified table
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param table Character. Schema-qualified table name.
#' @param exclude_generated Logical. If `TRUE`, exclude PostgreSQL
#'   `GENERATED ALWAYS` columns. Default `FALSE`.
#' @return Character vector of column names.
#' @noRd
.frs_table_columns <- function(conn, table, exclude_generated = FALSE) {
  tbl_parts <- strsplit(table, "\\.")[[1]]
  tbl_schema <- if (length(tbl_parts) == 2) tbl_parts[1] else "public"
  tbl_name <- tbl_parts[length(tbl_parts)]
  gen_filter <- if (exclude_generated) " AND is_generated = 'NEVER'" else ""
  sql <- sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = '%s' AND table_name = '%s'%s
     ORDER BY ordinal_position",
    tbl_schema, tbl_name, gen_filter
  )
  DBI::dbGetQuery(conn, sql)$column_name
}


#' Drop a test table from the working schema
#'
#' Convenience wrapper for integration test teardown.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param table Character. Schema-qualified table name (e.g.
#'   `"working.test_extract"`).
#' @return NULL invisibly.
#' @noRd
.frs_test_drop <- function(conn, table) {
  .frs_validate_identifier(table, "test table")
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", table))
  invisible(NULL)
}


#' Transform sf result to a target CRS
#'
#' @param x An `sf` object.
#' @param crs Target CRS (integer EPSG code, character proj4/WKT, or
#'   `sf::st_crs()` object). `NULL` returns `x` unchanged.
#' @return `x`, optionally transformed.
#' @noRd
.frs_transform <- function(x, crs = NULL) {
  if (is.null(crs)) return(x)
  sf::st_transform(x, crs)
}
