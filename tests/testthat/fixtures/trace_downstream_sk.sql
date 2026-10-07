INSERT INTO pg_temp.t (linear_feature_id)
     WITH origins AS (SELECT 1 AS origin_id),
     downstream AS (
       SELECT o.origin_id,
         t.linear_feature_id, t.gradient, t.wscode_ltree,
         t.downstream_route_measure,
         -t.length_metre + SUM(t.length_metre) OVER (
           PARTITION BY o.origin_id
           ORDER BY t.wscode_ltree DESC, t.downstream_route_measure DESC
         ) AS dist_to_origin
       FROM origins o
       INNER JOIN w.streams t ON FWA_Downstream(
         o.blue_line_key, o.downstream_route_measure,
         o.wscode_ltree, o.localcode_ltree,
         t.blue_line_key, t.downstream_route_measure,
         t.wscode_ltree, t.localcode_ltree)
       WHERE t.blue_line_key = t.watershed_key
     ),
     downstream_capped AS (
       SELECT row_number() OVER (
         PARTITION BY origin_id
         ORDER BY wscode_ltree DESC, downstream_route_measure DESC
       ) AS rn, *
       FROM downstream WHERE dist_to_origin < 3000
     ),
     nearest_barrier AS (
       SELECT DISTINCT ON (origin_id) *
       FROM downstream_capped WHERE gradient > 0.05
       ORDER BY origin_id, wscode_ltree DESC, downstream_route_measure DESC
     ),
     valid_downstream AS (
       SELECT d.linear_feature_id FROM downstream_capped d
       LEFT JOIN nearest_barrier nb ON d.origin_id = nb.origin_id
       WHERE nb.rn IS NULL OR d.rn < nb.rn
     )
     SELECT DISTINCT linear_feature_id FROM valid_downstream
