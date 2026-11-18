-- Desempeno de cada repartidor en los ultimos 30 dias: entregas, minutos medios
-- desde que acepta hasta que entrega y kilometros recorridos (sumando la
-- distancia entre posiciones consecutivas; se ignoran saltos de mas de 2 km o
-- 10 minutos, que son cortes de senal y no recorrido).
WITH posicion AS (
  SELECT repartidor_id, lat, lng, from_iso8601_timestamp(ts) AS t
  FROM posiciones
  WHERE fecha >= date_format(current_date - INTERVAL '30' DAY, '%Y-%m-%d')
    AND repartidor_id NOT LIKE 'simulacion-%'
),
tramo AS (
  SELECT repartidor_id,
         great_circle_distance(
           lag(lat) OVER (PARTITION BY repartidor_id ORDER BY t),
           lag(lng) OVER (PARTITION BY repartidor_id ORDER BY t),
           lat, lng) AS km,
         date_diff('second', lag(t) OVER (PARTITION BY repartidor_id ORDER BY t), t) AS segundos
  FROM posicion
),
recorrido AS (
  SELECT repartidor_id, round(sum(km), 1) AS km_recorridos
  FROM tramo
  WHERE km < 2 AND segundos <= 600
  GROUP BY repartidor_id
),
pedido AS (
  SELECT pedido_id,
         arbitrary(repartidor_id) AS repartidor_id,
         min(CASE WHEN estado = 'ASIGNADO' THEN from_iso8601_timestamp(ts) END) AS asignado,
         min(CASE WHEN estado = 'ENTREGADO' THEN from_iso8601_timestamp(ts) END) AS entregado
  FROM eventos_pedido
  WHERE fecha >= date_format(current_date - INTERVAL '30' DAY, '%Y-%m-%d')
  GROUP BY pedido_id
),
entregas AS (
  SELECT repartidor_id,
         count(*) AS entregas,
         round(avg(date_diff('second', asignado, entregado)) / 60.0, 1) AS min_medio_entrega
  FROM pedido
  WHERE entregado IS NOT NULL AND repartidor_id IS NOT NULL
  GROUP BY repartidor_id
)
SELECT coalesce(e.repartidor_id, r.repartidor_id) AS repartidor_id,
       coalesce(e.entregas, 0) AS entregas,
       e.min_medio_entrega,
       coalesce(r.km_recorridos, 0) AS km_recorridos
FROM entregas e
FULL OUTER JOIN recorrido r ON r.repartidor_id = e.repartidor_id
ORDER BY entregas DESC, km_recorridos DESC;
