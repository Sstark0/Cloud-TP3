-- Tiempos de entrega de los ultimos 30 dias, por comercio y hora del pedido
-- (hora de Buenos Aires): cuanto tarda en asignarse y en llegar al cliente.
WITH evento AS (
  SELECT pedido_id, comercio, estado, from_iso8601_timestamp(ts) AS t
  FROM eventos_pedido
  WHERE fecha >= date_format(current_date - INTERVAL '30' DAY, '%Y-%m-%d')
),
pedido AS (
  SELECT pedido_id,
         arbitrary(comercio) AS comercio,
         min(CASE WHEN estado = 'CREADO' THEN t END) AS creado,
         min(CASE WHEN estado = 'ASIGNADO' THEN t END) AS asignado,
         min(CASE WHEN estado = 'ENTREGADO' THEN t END) AS entregado
  FROM evento
  GROUP BY pedido_id
)
SELECT comercio,
       hour(creado AT TIME ZONE 'America/Argentina/Buenos_Aires') AS hora,
       count(*) AS pedidos_entregados,
       round(avg(date_diff('second', creado, asignado)) / 60.0, 1) AS min_hasta_asignar,
       round(avg(date_diff('second', asignado, entregado)) / 60.0, 1) AS min_asignado_a_entregado,
       round(avg(date_diff('second', creado, entregado)) / 60.0, 1) AS min_total
FROM pedido
WHERE creado IS NOT NULL AND entregado IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2;
