-- Pedidos rechazados (productos inexistentes) y cancelados (sin repartidor que
-- acepte) de los ultimos 30 dias, por comercio.
WITH pedido AS (
  SELECT pedido_id,
         arbitrary(comercio) AS comercio,
         max(CASE WHEN estado = 'RECHAZADO' THEN 1 ELSE 0 END) AS rechazado,
         max(CASE WHEN estado = 'CANCELADO' THEN 1 ELSE 0 END) AS cancelado,
         max(CASE WHEN estado = 'ENTREGADO' THEN 1 ELSE 0 END) AS entregado
  FROM eventos_pedido
  WHERE fecha >= date_format(current_date - INTERVAL '30' DAY, '%Y-%m-%d')
  GROUP BY pedido_id
)
SELECT coalesce(comercio, '(comercio inexistente)') AS comercio,
       count(*) AS pedidos,
       sum(entregado) AS entregados,
       sum(rechazado) AS rechazados,
       sum(cancelado) AS cancelados,
       round(100.0 * sum(rechazado + cancelado) / count(*), 1) AS pct_sin_entregar
FROM pedido
GROUP BY 1
ORDER BY pct_sin_entregar DESC;
