# Cumplimiento de la Propuesta 1 del TP1 con las limitaciones del Learner Lab

Compara lo propuesto en el TP1 ([TP1-G1.md](TP1-G1.md), Propuesta 1: *Plataforma de Ingesta y Procesamiento de Telemetría de Flota para Aplicaciones de Delivery*) con lo implementado en el repositorio.

Para cada punto que falta se separan tres casos:

- 🔒 **Lo bloquea el Lab**: no hay forma de hacerlo; alcanza con documentarlo y defenderlo.
- 💲 **Es solo costo**: el Lab lo permite, pero gasta crédito. Basta con una variable que lo active y una justificación.
- 🛠️ **No depende del Lab**: hay que hacerlo, porque en la defensa no se puede culpar al Lab.

Limitaciones tomadas en cuenta (ya comprobadas en [ARCHITECTURE-DEFENSE.md](ARCHITECTURE-DEFENSE.md)):

| ID | Limitación |
|---|---|
| L1 | No se pueden crear roles; todo corre con `LabRole`. |
| L2 | El SCP niega `kinesis:IncreaseStreamRetentionPeriod` y las llamadas de Object Lock del provider. |
| L3 | Solo se pueden usar us-east-1 y us-west-2. |
| L4 | El crédito es limitado y las sesiones vencen. |
| L5 | No hay acceso a Billing. |
| L6 | `LabRole` no tiene permisos para X-Ray ni para `rds-db:connect`. |

Los puntos que dependían del Lab se verificaron el 18/11/2026 sobre la cuenta del Learner Lab (ver [Resultados de la verificación](#resultados-de-la-verificación)).

---

## Veredicto

| Requisito | Qué falta | ¿Lo limita el Lab? | Veredicto |
|---|---|---|---|
| **F1** Ventana de retención configurable | Queda fija en 24 h | 🔒 Sí (L2) | ✅ Justificado |
| **F1** Absorber ráfagas sin aprovisionar | 1 shard provisionado | 💲 No: on-demand y cambio de shards probados en el Lab | 🟡 Agregar variable de modo/shards |
| **F2** Tiempo de preparación y carga | No se usan en la selección | 🛠️ No | 🔴 Hay que hacerlo |
| **F3** Seguimiento sin consultas periódicas | El frontend consulta en intervalos | 🛠️ No: `ManageConnections` permitido | 🔴 Hay que hacerlo |
| **F4** Escalado programado | — | — | ✅ Cumple: Scheduler por franjas sobre los shards del stream (probado en el Lab) |
| **F4** Escalado reactivo y contracción al mínimo | — | — | ✅ Cumple: Lambda + alarma de escrituras rechazadas sobre el stream (probado en el Lab) |
| **F5** Archivo de posiciones y lifecycle | — | — | ✅ Cumple |
| **F5** Archivo de eventos de pedidos | Quedan solo en RDS | 🛠️ No | 🔴 Hay que hacerlo |
| **F5** Panel analítico | Solo hay un dashboard operativo | 🔒 QuickSight sí está bloqueado; Glue y Athena no | 🟡 Resolver con Athena + CloudWatch |
| §1.3 Multi-AZ | Apagado por defecto | 💲 Costo (L4) | 🟡 Activarlo en la demo o defenderlo |
| §1.3 Multi-región | No existe | 🔒 Sí (L3) | ✅ Justificado (README §7) |
| §1.4 Tres consumidores independientes | Hay dos | 🛠️ No | 🔴 Se resuelve junto con F3 |

**El Lab solo justifica la retención de 24 h, la ausencia de multi-región y no usar QuickSight.** Los demás puntos que faltan tienen un camino posible dentro del Lab, y la verificación lo confirmó.

---

## Detalle por punto

### F1. Ingesta continua

Lo que ya cumple: punto de ingesta gestionado (`PUT /repartidores/me/posicion` → [registrar-posicion](terraform/organization/lambdas/registrar-posicion/handler.py) → Kinesis, con el repartidor como clave de partición) y consumidores independientes, cada uno con su event source mapping (posición inicial, lote, bisect, reintentos y cola `posiciones-fallidas`) en [streaming.tf](terraform/organization/streaming.tf).

- **Retención (justificada):** el SCP niega `kinesis:IncreaseStreamRetentionPeriod`, así que 24 h es la única ventana posible. En la prueba, el stream nuevo quedó con `RetentionPeriodHours = 24`.
  - Para defenderlo, conviene que la retención igual exista como parámetro en `recursos-base`, aunque solo acepte 24.
  - Ayuda mostrar que la cola `posiciones-fallidas` y el `TRIM_HORIZON` del archivador permiten recuperarse dentro de esas 24 h.
- **Ráfagas:** el Lab no bloquea ninguna de las dos opciones. En la prueba real funcionaron `UpdateShardCount` (de 1 a 2 shards) y `UpdateStreamMode` a `ON_DEMAND`. La cuenta admite 50 streams on-demand y 20.000 shards.
  - `recursos-base` ya pasa `StreamModeDetails`, así que alcanza con convertirlo en una variable `modo_stream` (`PROVISIONED`/`ON_DEMAND`) y escribir un párrafo que explique por qué la demo usa 1 shard (costo, L4).
  - Si se implementa F4 con cambio de shards, este punto queda cubierto de todas formas.

### F2. Motor de asignación

Lo que ya cumple: índice de repartidores disponibles (`repartidor.disponible` + `repartidor_posicion` con índice GiST) y reevaluación automática (rechazo, vencimiento u ocupado vuelven a `BuscarRepartidor` hasta `MAX_INTENTOS`).

No tiene ninguna relación con el Lab.

- Hay que agregar una columna `comercio.minutos_preparacion` (con valores en `seed.sql`).
- En [buscar-repartidor](terraform/organization/lambdas/buscar-repartidor/handler.py), el orden pasaría a ser un puntaje en lugar de la distancia sola. Por ejemplo: priorizar al repartidor cuyo tiempo de llegada al comercio se acerque más al tiempo de preparación, y penalizar la carga (pedidos del día o entregas recientes).
- Es un cambio chico y es el punto más fácil de cuestionar en la defensa.

### F3. Seguimiento en vivo, y de paso §1.4

Lo que ya cumple: el último estado se conserva y `GET /pedidos/{id}` reconstruye la vista al reconectar. Lo que falta: el cliente ve la posición con `usePolling` ([ClienteApp.jsx:468](frontend/src/cliente/ClienteApp.jsx#L468)), es decir, con consultas periódicas.

- La API WebSocket de API Gateway **no necesita roles nuevos**:
  - La integración con Lambda usa un `aws_lambda_permission`, que es una política de recurso y no un rol.
  - La Lambda que envía las posiciones usa `execute-api:ManageConnections` con `LabRole`, y el simulador lo da como permitido.
  - Las conexiones se guardan en una tabla de RDS (ya hay base y esquema) o en DynamoDB (`dynamodb:CreateTable` permitido).
- Esa Lambda sería un **tercer consumidor del stream**: lee las posiciones y las envía a los clientes suscritos al pedido. Así quedan cumplidos F3 y la arquitectura de §1.4 al mismo tiempo.
- Con tres consumidores por polling, cada shard recibe unas 3 lecturas por segundo, por debajo del límite de 5. No hace falta enhanced fan-out.
- Lo que ya funciona se conserva: al reconectar, `GET /pedidos/{id}` reconstruye la vista.

### F4. Escalado según la curva de demanda

> **Implementado** en la rama `feat/escalado-programado` ([escalado.tf](terraform/organization/escalado.tf), Lambda `escalar-capacidad`, README §7 "Escalado según la curva de demanda"). Probado en el Lab el 18/11/2026:
> - las acciones programadas `pico` y `base` llevaron el stream de 1 a 2 shards y de vuelta a 1;
> - una ráfaga de unos 1.200 registros/s disparó la alarma, que escaló de 1 a 2 y se rearmó;
> - el enfriamiento evitó duplicar de nuevo con los rechazos viejos que seguían en la ventana;
> - con 2 shards los rechazos bajaron a 0.
>
> El texto de abajo es el análisis previo a la implementación.

La verificación mostró que el Lab no bloquea el camino propuesto. Sí bloquea las alternativas basadas en concurrencia aprovisionada.

- **Parte programada, sin roles nuevos:** reglas de EventBridge con cron que invocan una Lambda `escalar-capacidad`. Una regla que apunta a una Lambda solo necesita `aws_lambda_permission`. También se puede usar EventBridge Scheduler con `LabRole`, porque `scheduler.amazonaws.com` está en su trust policy. Antes de almuerzo y cena, esa Lambda:
  - sube los shards de Kinesis con `UpdateShardCount`, que funcionó en la prueba real;
  - opcionalmente ajusta la concurrencia reservada de las Lambdas de la VPC (`PutFunctionConcurrency` permitido). Eso además pone un tope a las conexiones a RDS, un WEAKPOINT que el repo ya tiene anotado.
- **Parte reactiva:** Lambda ya escala sola. Se puede sumar una alarma sobre `WriteProvisionedThroughputExceeded` que dispare la misma Lambda.
- **Contracción al mínimo:** fuera de los picos se vuelve a 1 shard, y Lambda ya baja a cero.
- **Lo que el Lab bloquea:**
  - La concurrencia aprovisionada de Lambda: `PutProvisionedConcurrencyConfig` tiene un **deny explícito**.
  - Application Auto Scaling para Lambda: el rol vinculado al servicio no existe y `iam:CreateServiceLinkedRole` está denegado. De todas formas sería inútil sin concurrencia aprovisionada.
- **Lo que conviene evitar:** escalar RDS por horario, porque cambiar el tipo de instancia provoca una interrupción.
- El límite de concurrencia de Lambda de la cuenta es **400**, así que no frena una demo de picos.
- **Para la demo:** las sesiones vencen (L4), así que los horarios cron deberían ser variables, para poder disparar un "pico" durante la presentación.

### F5. Historial y panel analítico

Lo que ya cumple: archivo continuo de posiciones en `historico/posiciones/fecha=…/` y lifecycle Standard → Standard-IA (30 d) → Glacier IR (90 d) → borrado (180 d) en [storage.tf](terraform/organization/storage.tf).

- **Eventos de pedidos:** `notificar` ya está suscrito al topic `estado-pedido` y hoy solo escribe un log. Alcanza con que escriba JSONL en `historico/pedidos/fecha=…/`, que ya está cubierto por el lifecycle. No necesita roles.
  - Otra opción posible: Data Firehose, que puede asumir `LabRole` (ver la verificación).
- **Analítica:** Glue y Athena están permitidos y `glue.amazonaws.com` puede asumir `LabRole`, así que hasta un crawler sería posible. Lo más simple es:
  - un `aws_glue_catalog_table` definido en Terraform sobre `historico/`;
  - un workgroup de Athena con salida en el mismo bucket (prefijo `athena/`), así no se crea otro bucket (L2);
  - consultas guardadas con `aws_athena_named_query` para tiempos de entrega, cobertura y desempeño por repartidor.
- **Panel:** **QuickSight está bloqueado en el Lab** (`AccessDenied` en la llamada real). Es el único argumento de Lab válido en este punto.
  - Alternativa: métricas personalizadas en formato EMF desde `marcar-entregado` (tiempo de entrega, distancia) y una segunda pestaña "Analítica" en el dashboard de CloudWatch (`cloudwatch:PutMetricData` permitido).
  - Para análisis histórico, las consultas guardadas de Athena.

### §1.3. Alta disponibilidad

- La VPC y las subredes ya cubren 2 AZs. Lambda, Kinesis, S3, SQS, SNS y Step Functions son multi-AZ por diseño.
- RDS Multi-AZ y el endpoint en las dos AZs son **costo, no bloqueo**. Las variables ya existen, así que conviene desplegar al menos una vez con `db_multi_az = true` y `endpoint_una_az = false` para mostrarlo en la defensa, y bajarlo después.
- La recuperación en otra región sí está bloqueada (L3) y el README §7 ya lo justifica.

---

## Prioridades para la última entrega

1. ~~**F4, escalado programado y reactivo**~~ ✅ Implementado y probado en el Lab (rama `feat/escalado-programado`).
2. **F3 y §1.4, WebSocket como tercer consumidor.** Cierra dos puntos con un solo cambio.
3. **F2, tiempo de preparación y carga en la asignación.** Es lo más barato de resolver.
4. **F5, archivar eventos de pedidos, Glue + Athena y métricas EMF.**
5. **Variables y documentación:** modo del stream, retención fija por el SCP, y una demo Multi-AZ.

---

## Resultados de la verificación

Verificado el 18/11/2026 en la cuenta del Learner Lab (us-east-1), con sesión activa y sin el TP desplegado. Se usaron tres métodos:

- **Prueba real:** se hicieron las llamadas y se observó el resultado.
- **Lectura real:** una llamada de solo lectura al servicio. Confirma el acceso al servicio, pero no que se pueda crear.
- **Simulador:** `iam simulate-principal-policy` sobre `LabRole` (lo que pueden hacer las Lambdas) y sobre `voclabs` (lo que puede crear Terraform). **El simulador no evalúa el SCP de Academy**, así que un "permitido" del simulador todavía podría fallar en un despliegue real.

| Punto | Resultado | Método |
|---|---|---|
| `kinesis:UpdateShardCount` | ✅ Funciona (1 → 2 shards) | Prueba real |
| Kinesis modo `ON_DEMAND` | ✅ Funciona (`UpdateStreamMode`) | Prueba real |
| Retención de Kinesis | 24 h, sin cambios (L2) | Prueba real |
| Límites de Kinesis | 20.000 shards, 50 streams on-demand | Lectura real |
| Concurrencia de Lambda de la cuenta | 400 | Lectura real |
| `lambda:PutFunctionConcurrency` (reservada) | ✅ Permitido | Simulador |
| `lambda:PutProvisionedConcurrencyConfig` | 🔒 Deny explícito | Simulador |
| Application Auto Scaling para Lambda | 🔒 Sin rol vinculado al servicio; `iam:CreateServiceLinkedRole` denegado | Lectura real + simulador |
| EventBridge reglas / Scheduler | ✅ Permitido; `scheduler` y `events` en la trust policy de `LabRole` | Simulador + trust policy |
| `execute-api:ManageConnections` (WebSocket) | ✅ Permitido para `LabRole` | Simulador |
| Glue y Athena | ✅ Permitido; `glue` y `athena` en la trust policy | Lectura real + simulador |
| QuickSight | 🔒 Bloqueado (`AccessDenied`) | Lectura real |
| Data Firehose | ✅ `firehose` en la trust policy y creación permitida | Lectura real + simulador |
| DynamoDB | ✅ Permitido | Simulador |
| `iam:PassRole` de `LabRole` (para Terraform) | ✅ Permitido | Simulador |
| RDS Proxy | ✅ `rds` en la trust policy y `CreateDBProxy` permitido. Prueba del 20/11: proxy con `LabRole` y el secreto, target PostgreSQL 16 en `AVAILABLE` (~8 min el proxy, ~6 min más el target) | Prueba real |
| EventBridge Pipes | ✅ `pipes` en la trust policy y `CreatePipe` permitido | Lectura real + simulador |
| API Gateway → Step Functions directo | ✅ `apigateway` en la trust policy | Trust policy + simulador |
| Cost Anomaly Detection | ✅ Cost Explorer responde y `CreateAnomalyMonitor` permitido | Lectura real + simulador |
| CloudFront | 🔒 Bloqueado (`AccessDenied`) | Lectura real |
| Amplify Hosting | ✅ Permitido. Prueba del 20/11: `aws_amplify_app`/`aws_amplify_branch` con Terraform (create, refresh sin diferencias, destroy), despliegue manual del build real, HTTPS y reescritura de rutas de la SPA | Prueba real |
| Amazon Location Service | 🔒 Deny explícito | Lectura real + simulador |

Comandos usados:

```bash
ROLE=$(aws iam get-role --role-name LabRole --query Role.Arn --output text)
aws iam simulate-principal-policy --policy-source-arn "$ROLE" --action-names <acciones> \
  --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output table
aws iam get-role --role-name LabRole --query 'Role.AssumeRolePolicyDocument.Statement[].Principal'
aws lambda get-account-settings
aws kinesis describe-limits
# Prueba real (stream temporal, borrado al final):
aws kinesis create-stream --stream-name tp1-verificacion-shards --shard-count 1
aws kinesis update-shard-count --stream-name tp1-verificacion-shards --target-shard-count 2 --scaling-type UNIFORM_SCALING
aws kinesis update-stream-mode --stream-arn <arn> --stream-mode-details StreamMode=ON_DEMAND
aws kinesis delete-stream --stream-name tp1-verificacion-shards --enforce-consumer-deletion
```
