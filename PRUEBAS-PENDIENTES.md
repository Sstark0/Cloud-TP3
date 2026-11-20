# Pruebas pendientes: correcciones de la entrega

Cambios de la rama `correcciones-entrega`: dos buckets S3 (comprobantes e histórico), RDS Proxy y frontend en Amplify Hosting.

## Lo que ya se probó (20/11, sesión del Learner Lab)

| Prueba | Resultado |
|---|---|
| `terraform validate` y `terraform fmt -check` | OK |
| `terraform plan` contra el Lab con estado vacío | OK: 215 recursos a crear, incluidos el proxy, Amplify y la configuración de los dos buckets |
| Amplify con Terraform (`aws_amplify_app` + `aws_amplify_branch`, en una config aislada) | create OK; segundo `plan` sin diferencias; destroy OK |
| Despliegue manual del build real del frontend en Amplify (zip con `python -m zipfile`, igual que `scripts/publicar-frontend.sh`) | OK: `/`, `/cliente` y `/repartidor/pedido` → 200 con `index.html`; JS servido como `text/javascript`; asset inexistente → 404 |
| RDS Proxy con la CLI en la VPC por defecto (RDS PostgreSQL 16 `db.t3.micro` + secreto + proxy con `LabRole`) | OK: proxy `available` en ~8 min; target `AVAILABLE` ~6 min después (el proxy leyó el secreto y se autenticó) |
| `npm run build` del frontend | OK |
| Sintaxis de los scripts bash, Python y YAML | OK |

## Lo que falta (necesita un deploy completo: ~25 min el apply y 20–40 min el destroy)

1. **Deploy completo.** *Actions* → **deploy** → `apply`, con los secrets del Lab actualizados. El workflow publica el frontend y corre la prueba de humo, que ahora también verifica el frontend.
   - Mirar la salida de `aws_lambda_invocation.migrar_esquema`. Si aparecen líneas `proxy todavia no disponible` en el log de `delivery-migrar-esquema`, es lo esperado; tiene que terminar con `postgis` y `comercios`.
2. **Verificación completa.** Desde la raíz del repo, con las mismas credenciales: `./scripts/verificar-apply.sh`. Requiere configurar el backend remoto como en "Contraseñas demo" del README, para leer los outputs. Lo nuevo que chequea:
   - Target del proxy `AVAILABLE`, y que RDS solo acepte el 5432 desde el security group del proxy.
   - Posiciones en `posiciones/` del bucket `historico`; lifecycle a Glacier IR solo en `historico`; CORS POST solo en `comprobantes`.
   - Frontend: `/`, `/cliente` y `/repartidor` → 200, y CORS del API para la URL de Amplify.
3. **Prueba manual en el navegador** (URL del resumen del workflow, `https://main.<app>.amplifyapp.com`):
   - Cliente: login, catálogo, **crear un pedido** (usa `crypto.randomUUID`, que solo existe con HTTPS) y ver la ubicación del cliente.
   - Repartidor: login, GPS real del navegador (ya no cae en la simulación por HTTP), aceptar la oferta y **subir el comprobante** (POST firmado al bucket `comprobantes`) para confirmar la entrega.
   - En S3: la foto en el bucket `delivery-comprobantes-*`, clave `<pedido>/<sub>.jpg` (ya sin prefijo `comprobantes/`), y los eventos en el bucket `delivery-historico-*`, `pedidos/fecha=.../`.
   - En Athena (workgroup `delivery-analitica`): correr `tiempos_entrega` o `curva_demanda`.
4. **Proxy bajo carga (opcional, para la defensa).** Con varias ventanas haciendo pedidos, el dashboard `delivery-operacion` → widget "RDS: conexiones" muestra `ClientConnections` del proxy por encima de las `DatabaseConnections` que el proxy abre a la base.
5. **Destroy.** *Run workflow* → `destroy`. Confirmar que no quedan los buckets `delivery-comprobantes-*` / `delivery-historico-*`, ni el proxy, ni la app de Amplify.

## Puntos a observar en el primer deploy

- **Lectura del secreto por el proxy.** No está documentado si RDS Proxy lee el secreto desde sus interfaces en la VPC o por la red interna de AWS. La VPC no tiene NAT, así que el proxy quedó en las subredes `app` con salida 443 al endpoint de Secrets Manager, por las dudas. Si el target queda en `UNAVAILABLE` con motivo `AUTH_FAILURE` o un problema de conexión al secreto, revisar esto primero. La prueba del 20/11 fue en la VPC por defecto, que sí tiene salida a internet.
- **TLS al proxy.** `db.py` ahora confía en las CA del sistema (el certificado del proxy es de Amazon Trust Services) además del bundle de RDS. Si una Lambda falla con `SSLCertVerificationError`, el problema está ahí.
- **Tiempo del apply.** El proxy agrega ~15 min entre que se crea y que su target queda disponible. El workflow tiene `timeout-minutes: 60`.
