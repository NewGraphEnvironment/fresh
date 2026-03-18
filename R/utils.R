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
#' Subsurface flow (edge_type 1410/1425 — underground conduits, culverts)
#' is NOT filtered by default because these are real network connectivity.
#' Use [.frs_snap_guards()] for snap-specific filtering that excludes
#' subsurface segments.
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
#' (edge_type 1410/1425 — underground conduits). Used by the KNN snap
#' path where snapping to a culvert is not useful.
#'
#' @inheritParams .frs_stream_guards
#' @return Character vector of SQL predicates.
#' @noRd
.frs_snap_guards <- function(alias = "s", wscode_col = "wscode_ltree",
                             localcode_col = "localcode_ltree") {
  c(
    .frs_stream_guards(alias, wscode_col, localcode_col),
    {
      prefix <- if (nzchar(alias)) paste0(alias, ".") else ""
      paste0(prefix, "edge_type NOT IN (1410, 1425)")
    }
  )
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
