CREATE TEMP TABLE w AS
SELECT s.linear_feature_id AS id_segment, s.blue_line_key, s.watershed_key, s.downstream_route_measure,
       s.wscode_ltree, s.localcode_ltree, s.edge_type, s.waterbody_key, s.length_metre, s.geom,
       nullif(q.q_m3s, 0) AS mad_m3s
FROM whse_basemapping.fwa_stream_networks_sp s
LEFT JOIN discharge.fwa_v1_segment_monthly q ON q.linear_feature_id = s.linear_feature_id
     AND q.scenario = 'historical' AND q.month = 0 AND q.pick
WHERE s.watershed_group_code = 'BULK' AND s.localcode_ltree IS NOT NULL
  AND s.edge_type <> 6010 AND NOT s.wscode_ltree <@ '999'::ltree;
CREATE INDEX ON w USING gist (geom); CREATE INDEX ON w USING gist (wscode_ltree); CREATE INDEX ON w USING gist (localcode_ltree);
ANALYZE w;
-- path rows per origin within 1 km, in path order; find the nearest target and any same-polygon connector AFTER it
WITH d AS (
  SELECT o.id_segment AS origin_id, t.id_segment, t.edge_type, t.waterbody_key, t.mad_m3s, t.wscode_ltree, t.downstream_route_measure,
         row_number() OVER (PARTITION BY o.id_segment ORDER BY t.wscode_ltree DESC, t.downstream_route_measure DESC) rn,
         -t.length_metre + SUM(t.length_metre) OVER (PARTITION BY o.id_segment ORDER BY t.wscode_ltree DESC, t.downstream_route_measure DESC) dist
  FROM w o JOIN w t ON FWA_Downstream(o.blue_line_key, o.downstream_route_measure, o.wscode_ltree, o.localcode_ltree,
                                      t.blue_line_key, t.downstream_route_measure, t.wscode_ltree, t.localcode_ltree)
  WHERE t.blue_line_key = t.watershed_key AND ST_DWithin(t.geom, o.geom, 1000)
), tgt AS (
  SELECT DISTINCT ON (origin_id) * FROM d WHERE mad_m3s >= 3 AND edge_type NOT IN (1400,1450) AND dist <= 1100 ORDER BY origin_id, rn
)
SELECT count(*) targets,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM d WHERE d.origin_id = tgt.origin_id AND d.edge_type IN (1400,1450)
                                         AND d.waterbody_key = tgt.waterbody_key AND d.rn > tgt.rn)) connector_after_target,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM d WHERE d.origin_id = tgt.origin_id AND d.edge_type IN (1400,1450)
                                         AND d.waterbody_key = tgt.waterbody_key AND d.rn < tgt.rn)) connector_before_target
FROM tgt;
