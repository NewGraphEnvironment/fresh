#' Validate Cluster Connectivity on Stream Network
#'
#' Check whether clusters of segments sharing one label are connected
#' to segments with another label on the stream network. Disconnected
#' clusters have their label set to `FALSE`.
#'
#' Uses `ST_ClusterDBSCAN(geom, 1, 1)` to group physically adjacent
#' segments, then validates each cluster by checking for
#' `label_connect` in the specified direction.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [frs_db_conn()]).
#' @param table Character. Schema-qualified streams table with geometry
#'   and ltree columns (from [frs_network_segment()]).
#' @param habitat Character. Schema-qualified habitat table with boolean
#'   label columns (from [frs_habitat_classify()]).
#' @param label_cluster Character. Boolean column name in `habitat` to
#'   cluster on. Default `"rearing"`.
#' @param label_connect Character. Boolean column name in `habitat` that
#'   must exist in the specified direction for a cluster to be valid.
#'   Default `"spawning"`.
#' @param species Character vector or `NULL`. Species codes to process.
#'   `NULL` processes all species in the habitat table. Default `NULL`.
#' @param direction Character. Where the connection must be relative to
#'   the cluster: `"upstream"`, `"downstream"`, or `"both"`. Default
#'   `"upstream"`.
#' @param bridge_gradient Numeric. Maximum gradient on any single segment
#'   between cluster and connection. Only applies to `"downstream"`
#'   direction. Default `0.05` (5%).
#' @param bridge_distance Numeric. Maximum network distance in metres to
#'   search for connection. Only applies to `"downstream"` direction.
#'   Default `10000` (10 km).
#' @param confluence_m Numeric. Confluence tolerance in metres. When a
#'   cluster's most-downstream point is within this distance of a
#'   confluence, the upstream check also considers the parent stream.
#'   Default `10`.
#' @param verbose Logical. Print progress. Default `TRUE`.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @family habitat
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # --- Why cluster connectivity matters ---
#' #
#' # frs_habitat_classify() labels segments as rearing or spawning
#' # based on gradient and channel width. But a rearing segment has
#' # no ecological value for anadromous species unless juveniles can
#' # reach spawning habitat. A headwater stream with perfect rearing
#' # conditions but no spawning upstream or downstream is a dead end.
#' #
#' # frs_cluster() groups adjacent rearing segments into clusters,
#' # then checks if each cluster connects to spawning on the network.
#' # Disconnected clusters get rearing set to FALSE.
#'
#' # After frs_network_segment() + frs_habitat_classify():
#' DBI::dbGetQuery(conn, "
#'   SELECT count(*) FILTER (WHERE rearing) AS rearing_before
#'   FROM fresh.streams_habitat
#'   WHERE species_code = 'CO'")
#' #>   rearing_before
#' #> 1             33
#'
#' # Upstream check: keep rearing only if spawning exists upstream.
#' # Anadromous juveniles rear downstream of where adults spawn.
#' frs_cluster(conn,
#'   table = "fresh.streams",
#'   habitat = "fresh.streams_habitat",
#'   species = "CO",
#'   direction = "upstream")
#' #>   CO: 2 disconnected removed (31 rearing remaining, 0.6s)
#'
#' # Downstream check: keep rearing only if spawning exists downstream
#' # within 10km, with no segment steeper than 5% in between.
#' # Juveniles can drift downstream but can't pass steep barriers
#' # to reach spawning habitat above.
#' frs_cluster(conn,
#'   table = "fresh.streams",
#'   habitat = "fresh.streams_habitat",
#'   species = "CO",
#'   direction = "downstream",
#'   bridge_gradient = 0.05,
#'   bridge_distance = 10000)
#'
#' # Both directions — valid if connected in either direction.
#' # Run per species with parameters from parameters_fresh.csv:
#' pf <- utils::read.csv(system.file("extdata",
#'   "parameters_fresh.csv", package = "fresh"))
#' for (i in which(pf$cluster_rearing)) {
#'   sp <- pf$species_code[i]
#'   frs_cluster(conn,
#'     table = "fresh.streams",
#'     habitat = "fresh.streams_habitat",
#'     species = sp,
#'     direction = pf$cluster_direction[i],
#'     bridge_gradient = pf$cluster_bridge_gradient[i],
#'     bridge_distance = pf$cluster_bridge_distance[i],
#'     confluence_m = pf$cluster_confluence_m[i])
#' }
#'
#' DBI::dbDisconnect(conn)
#' }
frs_cluster <- function(conn, table, habitat,
                        label_cluster = "rearing",
                        label_connect = "spawning",
                        species = NULL,
                        direction = "upstream",
                        bridge_gradient = 0.05,
                        bridge_distance = 10000,
                        confluence_m = 10,
                        verbose = TRUE) {
  .frs_validate_identifier(table, "streams table")
  .frs_validate_identifier(habitat, "habitat table")
  .frs_validate_identifier(label_cluster, "label_cluster column")
  .frs_validate_identifier(label_connect, "label_connect column")
  stopifnot(is.character(label_cluster), length(label_cluster) == 1)
  stopifnot(is.character(label_connect), length(label_connect) == 1)
  stopifnot(direction %in% c("upstream", "downstream", "both"))
  stopifnot(is.numeric(bridge_gradient), length(bridge_gradient) == 1)
  stopifnot(is.numeric(bridge_distance), length(bridge_distance) == 1)
  stopifnot(is.numeric(confluence_m), length(confluence_m) == 1)

  # Resolve species list
  if (is.null(species)) {
    species <- DBI::dbGetQuery(conn, sprintf(
      "SELECT DISTINCT species_code FROM %s", habitat
    ))$species_code
  }

  for (sp in species) {
    t0 <- proc.time()

    n_before <- 0L
    if (verbose) {
      n_before <- DBI::dbGetQuery(conn, sprintf(
        "SELECT count(*) FILTER (WHERE %s)::int AS n FROM %s
         WHERE species_code = %s",
        label_cluster, habitat, .frs_quote_string(sp)))$n
    }

    if (direction == "both") {
      # Both directions evaluated independently on original data,
      # then combined: valid if connected in EITHER direction
      .frs_cluster_both(conn, table, habitat,
        label_cluster, label_connect, sp,
        confluence_m, bridge_gradient, bridge_distance)
    } else if (direction == "upstream") {
      .frs_cluster_upstream(conn, table, habitat,
        label_cluster, label_connect, sp, confluence_m)
    } else {
      .frs_cluster_downstream(conn, table, habitat,
        label_cluster, label_connect, sp,
        bridge_gradient, bridge_distance)
    }

    if (verbose) {
      n_after <- DBI::dbGetQuery(conn, sprintf(
        "SELECT count(*) FILTER (WHERE %s)::int AS n FROM %s
         WHERE species_code = %s",
        label_cluster, habitat, .frs_quote_string(sp)))$n
      elapsed <- round((proc.time() - t0)["elapsed"], 1)
      cat("  ", sp, ": ", n_before - n_after, " disconnected removed (",
          n_after, " ", label_cluster, " remaining, ", elapsed, "s)\n",
          sep = "")
    }
  }

  invisible(conn)
}


#' Upstream cluster connectivity check
#'
#' For each cluster of `label_cluster` segments, check if `label_connect`
#' exists upstream of the cluster's most-downstream point. Sets
#' `label_cluster = FALSE` for segments in clusters that fail.
#'
#' Uses 8-arg `FWA_Upstream()` for positional precision. When the
#' cluster minimum is within `confluence_m` of a confluence, also
#' checks the parent stream via `subpath(wscode_ltree, 0, -1)`.
#'
#' @noRd
.frs_cluster_upstream <- function(conn, table, habitat,
                                  label_cluster, label_connect,
                                  species, confluence_m) {
  sp_quoted <- .frs_quote_string(species)
  conf_m <- .frs_sql_num(confluence_m)

  sql <- sprintf(
    "WITH clustering AS (
       SELECT
         h.id_segment,
         ST_ClusterDBSCAN(s.geom, 1, 1) OVER () AS cluster_id,
         s.wscode_ltree,
         s.localcode_ltree,
         s.blue_line_key,
         s.downstream_route_measure
       FROM %s h
       INNER JOIN %s s ON h.id_segment = s.id_segment
       WHERE h.species_code = %s
         AND h.%s IS TRUE
     ),

     cluster_minimums AS (
       SELECT DISTINCT ON (cluster_id)
         cluster_id,
         wscode_ltree,
         localcode_ltree,
         blue_line_key,
         downstream_route_measure
       FROM clustering
       ORDER BY cluster_id,
                wscode_ltree ASC,
                localcode_ltree ASC,
                downstream_route_measure ASC
     ),

     valid_clusters AS (
       SELECT DISTINCT cm.cluster_id
       FROM cluster_minimums cm
       INNER JOIN %s h2 ON h2.species_code = %s
         AND h2.%s IS TRUE
       INNER JOIN %s st ON h2.id_segment = st.id_segment
       WHERE
         FWA_Upstream(
           cm.blue_line_key, cm.downstream_route_measure,
           cm.wscode_ltree, cm.localcode_ltree,
           st.blue_line_key, st.downstream_route_measure,
           st.wscode_ltree, st.localcode_ltree
         )
         OR (
           cm.downstream_route_measure < %s
           AND FWA_Upstream(
             subpath(cm.wscode_ltree, 0, -1), cm.wscode_ltree,
             st.wscode_ltree, st.localcode_ltree
           )
         )
     )

     UPDATE %s h
     SET %s = FALSE
     FROM clustering c
     WHERE h.id_segment = c.id_segment
       AND h.species_code = %s
       AND c.cluster_id NOT IN (SELECT cluster_id FROM valid_clusters)",
    habitat, table, sp_quoted, label_cluster,
    habitat, sp_quoted, label_connect, table,
    conf_m,
    habitat, label_cluster, sp_quoted)

  .frs_db_execute(conn, sql)
}


#' Downstream cluster connectivity check
#'
#' For each cluster of `label_cluster` segments, trace downstream along
#' the mainstem using `fwa_downstreamtrace()`. Check if `label_connect`
#' exists within `bridge_distance`, with no segment exceeding
#' `bridge_gradient` between the cluster and the connection.
#'
#' @noRd
.frs_cluster_downstream <- function(conn, table, habitat,
                                    label_cluster, label_connect,
                                    species, bridge_gradient,
                                    bridge_distance) {
  sp_quoted <- .frs_quote_string(species)
  bg <- .frs_sql_num(bridge_gradient)
  bd <- .frs_sql_num(bridge_distance)

  sql <- sprintf(
    "WITH clustering AS (
       SELECT
         h.id_segment,
         ST_ClusterDBSCAN(s.geom, 1, 1) OVER () AS cluster_id,
         s.wscode_ltree,
         s.localcode_ltree,
         s.blue_line_key,
         s.downstream_route_measure
       FROM %s h
       INNER JOIN %s s ON h.id_segment = s.id_segment
       WHERE h.species_code = %s
         AND h.%s IS TRUE
     ),

     cluster_minimums AS (
       SELECT DISTINCT ON (cluster_id)
         cluster_id,
         wscode_ltree,
         localcode_ltree,
         blue_line_key,
         downstream_route_measure
       FROM clustering
       ORDER BY cluster_id,
                wscode_ltree ASC,
                localcode_ltree ASC,
                downstream_route_measure ASC
     ),

     downstream AS (
       SELECT
         cm.cluster_id,
         t.linear_feature_id,
         t.blue_line_key,
         t.wscode,
         t.downstream_route_measure,
         t.gradient,
         EXISTS (
           SELECT 1 FROM %s s
           INNER JOIN %s h2 ON s.id_segment = h2.id_segment
           WHERE s.linear_feature_id = t.linear_feature_id
             AND h2.species_code = %s
             AND h2.%s IS TRUE
         ) AS has_connect,
         -t.length_metre + SUM(t.length_metre) OVER (
           PARTITION BY cm.cluster_id
           ORDER BY t.wscode DESC, t.downstream_route_measure DESC
         ) AS dist_to_cluster
       FROM cluster_minimums cm
       CROSS JOIN LATERAL whse_basemapping.fwa_downstreamtrace(
         cm.blue_line_key,
         cm.downstream_route_measure
       ) t
       WHERE t.blue_line_key = t.watershed_key
     ),

     downstream_capped AS (
       SELECT
         row_number() OVER (
           PARTITION BY cluster_id
           ORDER BY wscode DESC, downstream_route_measure DESC
         ) AS rn,
         *
       FROM downstream
       WHERE dist_to_cluster < %s
     ),

     nearest_connect AS (
       SELECT DISTINCT ON (cluster_id) *
       FROM downstream_capped
       WHERE has_connect IS TRUE
       ORDER BY cluster_id, wscode DESC, downstream_route_measure DESC
     ),

     nearest_barrier AS (
       SELECT DISTINCT ON (cluster_id) *
       FROM downstream_capped
       WHERE gradient >= %s
       ORDER BY cluster_id, wscode DESC, downstream_route_measure DESC
     ),

     valid_clusters AS (
       SELECT a.cluster_id
       FROM nearest_connect a
       LEFT JOIN nearest_barrier b ON a.cluster_id = b.cluster_id
       WHERE b.rn IS NULL OR b.rn > a.rn
     )

     UPDATE %s h
     SET %s = FALSE
     FROM clustering c
     WHERE h.id_segment = c.id_segment
       AND h.species_code = %s
       AND c.cluster_id NOT IN (SELECT cluster_id FROM valid_clusters)",
    habitat, table, sp_quoted, label_cluster,
    table, habitat, sp_quoted, label_connect,
    bd,
    bg,
    habitat, label_cluster, sp_quoted)

  .frs_db_execute(conn, sql)
}


#' Both-direction cluster connectivity check
#'
#' Evaluates upstream and downstream independently on the original data,
#' then combines: a cluster is valid if connected in either direction.
#' Uses a temp table for clustering so both checks see the same clusters.
#'
#' @noRd
.frs_cluster_both <- function(conn, table, habitat,
                              label_cluster, label_connect,
                              species, confluence_m,
                              bridge_gradient, bridge_distance) {
  sp_quoted <- .frs_quote_string(species)
  conf_m <- .frs_sql_num(confluence_m)
  bg <- .frs_sql_num(bridge_gradient)
  bd <- .frs_sql_num(bridge_distance)

  tmp_clusters <- sprintf("pg_temp.frs_clusters_%s",
    gsub("[^a-z0-9]", "", tolower(species)))

  # Create shared clustering temp table
  .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", tmp_clusters))
  .frs_db_execute(conn, sprintf(
    "CREATE TEMP TABLE %s AS
     SELECT
       h.id_segment,
       ST_ClusterDBSCAN(s.geom, 1, 1) OVER () AS cluster_id,
       s.wscode_ltree,
       s.localcode_ltree,
       s.blue_line_key,
       s.downstream_route_measure
     FROM %s h
     INNER JOIN %s s ON h.id_segment = s.id_segment
     WHERE h.species_code = %s
       AND h.%s IS TRUE",
    tmp_clusters, habitat, table, sp_quoted, label_cluster))

  .frs_db_execute(conn, sprintf(
    "CREATE INDEX ON %s (cluster_id)", tmp_clusters))

  # Upstream valid clusters
  sql_upstream <- sprintf(
    "WITH cluster_minimums AS (
       SELECT DISTINCT ON (cluster_id)
         cluster_id, wscode_ltree, localcode_ltree,
         blue_line_key, downstream_route_measure
       FROM %s
       ORDER BY cluster_id, wscode_ltree ASC, localcode_ltree ASC,
                downstream_route_measure ASC
     )
     SELECT DISTINCT cm.cluster_id
     FROM cluster_minimums cm
     INNER JOIN %s h2 ON h2.species_code = %s
       AND h2.%s IS TRUE
     INNER JOIN %s st ON h2.id_segment = st.id_segment
     WHERE
       FWA_Upstream(
         cm.blue_line_key, cm.downstream_route_measure,
         cm.wscode_ltree, cm.localcode_ltree,
         st.blue_line_key, st.downstream_route_measure,
         st.wscode_ltree, st.localcode_ltree
       )
       OR (
         cm.downstream_route_measure < %s
         AND FWA_Upstream(
           subpath(cm.wscode_ltree, 0, -1), cm.wscode_ltree,
           st.wscode_ltree, st.localcode_ltree
         )
       )",
    tmp_clusters,
    habitat, sp_quoted, label_connect, table,
    conf_m)

  valid_up <- DBI::dbGetQuery(conn, sql_upstream)$cluster_id

  # Downstream valid clusters
  sql_downstream <- sprintf(
    "WITH cluster_minimums AS (
       SELECT DISTINCT ON (cluster_id)
         cluster_id, wscode_ltree, localcode_ltree,
         blue_line_key, downstream_route_measure
       FROM %s
       ORDER BY cluster_id, wscode_ltree ASC, localcode_ltree ASC,
                downstream_route_measure ASC
     ),
     downstream AS (
       SELECT
         cm.cluster_id,
         t.linear_feature_id,
         t.wscode,
         t.downstream_route_measure,
         t.gradient,
         EXISTS (
           SELECT 1 FROM %s s
           INNER JOIN %s h2 ON s.id_segment = h2.id_segment
           WHERE s.linear_feature_id = t.linear_feature_id
             AND h2.species_code = %s
             AND h2.%s IS TRUE
         ) AS has_connect,
         -t.length_metre + SUM(t.length_metre) OVER (
           PARTITION BY cm.cluster_id
           ORDER BY t.wscode DESC, t.downstream_route_measure DESC
         ) AS dist_to_cluster
       FROM cluster_minimums cm
       CROSS JOIN LATERAL whse_basemapping.fwa_downstreamtrace(
         cm.blue_line_key,
         cm.downstream_route_measure
       ) t
       WHERE t.blue_line_key = t.watershed_key
     ),
     downstream_capped AS (
       SELECT
         row_number() OVER (
           PARTITION BY cluster_id
           ORDER BY wscode DESC, downstream_route_measure DESC
         ) AS rn,
         *
       FROM downstream
       WHERE dist_to_cluster < %s
     ),
     nearest_connect AS (
       SELECT DISTINCT ON (cluster_id) *
       FROM downstream_capped
       WHERE has_connect IS TRUE
       ORDER BY cluster_id, wscode DESC, downstream_route_measure DESC
     ),
     nearest_barrier AS (
       SELECT DISTINCT ON (cluster_id) *
       FROM downstream_capped
       WHERE gradient >= %s
       ORDER BY cluster_id, wscode DESC, downstream_route_measure DESC
     )
     SELECT a.cluster_id
     FROM nearest_connect a
     LEFT JOIN nearest_barrier b ON a.cluster_id = b.cluster_id
     WHERE b.rn IS NULL OR b.rn > a.rn",
    tmp_clusters,
    table, habitat, sp_quoted, label_connect,
    bd,
    bg)

  valid_down <- DBI::dbGetQuery(conn, sql_downstream)$cluster_id

  # Union of both valid sets
  all_valid <- unique(c(valid_up, valid_down))

  # UPDATE: set FALSE for segments in clusters NOT valid in either direction
  if (length(all_valid) == 0) {
    .frs_db_execute(conn, sprintf(
      "UPDATE %s h SET %s = FALSE
       FROM %s c
       WHERE h.id_segment = c.id_segment
         AND h.species_code = %s",
      habitat, label_cluster, tmp_clusters, sp_quoted))
  } else {
    valid_list <- paste(as.integer(all_valid), collapse = ", ")
    .frs_db_execute(conn, sprintf(
      "UPDATE %s h SET %s = FALSE
       FROM %s c
       WHERE h.id_segment = c.id_segment
         AND h.species_code = %s
         AND c.cluster_id NOT IN (%s)",
      habitat, label_cluster, tmp_clusters, sp_quoted, valid_list))
  }

  .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", tmp_clusters))
}
