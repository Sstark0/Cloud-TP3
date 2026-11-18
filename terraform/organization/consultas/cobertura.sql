-- Cobertura de la flota en los ultimos 7 dias: posiciones agrupadas en celdas de
-- unos 500 m por hora del dia. Muestra donde hubo repartidores y donde no.
-- Se excluyen los repartidores ficticios de scripts/simular-pico.sh.
SELECT round(lat / 0.0045) * 0.0045 AS celda_lat,
       round(lng / 0.0055) * 0.0055 AS celda_lng,
       hour(from_iso8601_timestamp(ts) AT TIME ZONE 'America/Argentina/Buenos_Aires') AS hora,
       count(DISTINCT repartidor_id) AS repartidores,
       count(*) AS posiciones
FROM posiciones
WHERE fecha >= date_format(current_date - INTERVAL '7' DAY, '%Y-%m-%d')
  AND repartidor_id NOT LIKE 'simulacion-%'
GROUP BY 1, 2, 3
ORDER BY repartidores DESC, posiciones DESC;
