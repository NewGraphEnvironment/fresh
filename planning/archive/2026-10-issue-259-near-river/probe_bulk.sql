\timing on
-- BULK working-table stand-in: FWA rows of the group with localcode, no 6010/999, wet pick as mad_m3s
CREATE TEMP TABLE w AS
SELECT s.linear_feature_id AS id_segment, s.blue_line_key, s.watershed_key, s.downstream_route_measure,
       s.wscode_ltree, s.localcode_ltree, s.edge_type, s.waterbody_key, s.length_metre, s.geom,
       nullif(q.q_m3s, 0) AS mad_m3s
FROM whse_basemapping.fwa_stream_networks_sp s
LEFT JOIN discharge.fwa_v1_segment_monthly q ON q.linear_feature_id = s.linear_feature_id
     AND q.scenario = 'historical' AND q.month = 0 AND q.pick
WHERE s.watershed_group_code = 'BULK' AND s.localcode_ltree IS NOT NULL
  AND s.edge_type <> 6010 AND NOT s.wscode_ltree <@ '999'::ltree;
CREATE INDEX ON w USING gist (geom);
CREATE INDEX ON w USING gist (wscode_ltree); CREATE INDEX ON w USING gist (localcode_ltree);
CREATE INDEX ON w (blue_line_key, downstream_route_measure);
ANALYZE w;
SELECT count(*) n, count(mad_m3s) with_mad, count(*) FILTER (WHERE mad_m3s >= 3) ge3 FROM w;

CREATE TEMP TABLE near AS
WITH downstream AS (
  SELECT o.id_segment AS origin_id, t.id_segment, t.edge_type, t.waterbody_key, t.mad_m3s,
         t.wscode_ltree, t.downstream_route_measure,
         -t.length_metre + SUM(t.length_metre) OVER (PARTITION BY o.id_segment
            ORDER BY t.wscode_ltree DESC, t.downstream_route_measure DESC) AS dist_to_origin,
         SUM(t.length_metre) FILTER (WHERE t.edge_type IN (1400, 1450)) OVER (
            PARTITION BY o.id_segment, t.waterbody_key
            ORDER BY t.wscode_ltree DESC, t.downstream_route_measure DESC) AS conn_len
  FROM w o
  INNER JOIN w t ON FWA_Downstream(o.blue_line_key, o.downstream_route_measure, o.wscode_ltree, o.localcode_ltree,
                                   t.blue_line_key, t.downstream_route_measure, t.wscode_ltree, t.localcode_ltree)
  WHERE t.blue_line_key = t.watershed_key AND ST_DWithin(t.geom, o.geom, 1000)
)
SELECT DISTINCT ON (origin_id) origin_id, id_segment AS target, edge_type, waterbody_key, mad_m3s,
       dist_to_origin AS dist_centre, dist_to_origin - coalesce(conn_len, 0) AS dist_bank
FROM downstream
WHERE mad_m3s >= 3 AND edge_type NOT IN (1400, 1450) AND dist_to_origin - coalesce(conn_len, 0) <= 1000
ORDER BY origin_id, wscode_ltree DESC, downstream_route_measure DESC;

SELECT count(*) origins_hit, count(*) FILTER (WHERE dist_centre > 1000) only_by_bank,
       count(*) FILTER (WHERE dist_bank < dist_centre) bank_differs,
       round(avg(dist_centre - dist_bank)::numeric, 1) mean_conn_subtracted,
       count(*) FILTER (WHERE edge_type = 1250) target_1250, count(*) FILTER (WHERE edge_type = 1000) target_1000,
       count(*) FILTER (WHERE edge_type = 1200) target_1200
FROM near;
