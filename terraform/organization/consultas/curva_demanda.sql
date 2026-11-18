-- Curva de demanda de los ultimos 30 dias: pedidos por dia de la semana y hora
-- (hora de Buenos Aires). Es la que justifica las franjas del escalado.
SELECT day_of_week(t) AS dia_semana, -- 1 = lunes ... 7 = domingo
       hour(t) AS hora,
       count(*) AS pedidos
FROM (
  SELECT from_iso8601_timestamp(ts) AT TIME ZONE 'America/Argentina/Buenos_Aires' AS t
  FROM eventos_pedido
  WHERE estado = 'CREADO'
    AND fecha >= date_format(current_date - INTERVAL '30' DAY, '%Y-%m-%d')
)
GROUP BY 1, 2
ORDER BY 1, 2;
