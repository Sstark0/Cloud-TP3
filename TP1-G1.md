# 82.08 Cloud Computing — Trabajo Práctico N°1 (Grupo 1)

Instituto Tecnológico de Buenos Aires — Fecha de entrega: 19/08/2026

Integrantes: Andrés Cortese (64612), Tomas Jeronimo Esquivel (64756), Stella Figueirado Kirkvaag (69479), Joshua Kevin Jürgen Prieth, Antonio Uriel Serrano Jaimes (69525).

> Transcripción del PDF `TP1+-+G1.pdf` para lecturas futuras. La propuesta elegida para el proyecto es la **Propuesta 1**.

---

## 1. Plataforma de Ingesta y Procesamiento de Telemetría de Flota para Aplicaciones de Delivery

Se propone una plataforma en la nube que recibe la posición de los repartidores de una aplicación de delivery, la procesa en tiempo real para asignar y reasignar pedidos, y conserva el historial para su análisis posterior.

### 1.2. Introducción y Contexto Detallado

En las aplicaciones de reparto a domicilio, la operación depende de conocer en todo momento dónde está cada repartidor. Con flotas de miles de repartidores emitiendo su posición cada pocos segundos, el flujo de eventos es permanente pero muy desigual, se concentra en las franjas de almuerzo y cena y se dispara ante eventos climáticos. Sobre infraestructura propia esto obliga a dimensionar para el peor caso, dejando la capacidad sobrante casi todo el día.

### 1.3. Justificación de la Necesidad y Ventaja Estratégica Cloud

En primer lugar, la elasticidad permite que la capacidad de cómputo acompañe la curva horaria de la demanda, y el pago por uso hace que el costo sea proporcional a la actividad real del servicio. Los servicios gestionados de ingesta absorben las ráfagas imprevistas sin aprovisionamiento anticipado, y la alta disponibilidad en múltiples zonas resulta indispensable en un servicio ininterrumpido cuya caída implica pérdida directa de ventas.

### 1.4. Propuesta de Solución en la Nube

La aplicación del repartidor publica su posición contra un punto de ingesta gestionado en la nube. Ese flujo es consumido de forma independiente por el motor de asignación de pedidos, el servicio de seguimiento en vivo y el archivado analítico, de modo que un pico de emisión no propague demoras hacia los demás componentes.

### 1.5. Funcionalidades Clave

**Funcionalidad 1: Ingesta Continua de Telemetría de la Flota**
El sistema recibirá la posición de todos los repartidores activos mediante un punto de ingesta gestionado, que conservará los eventos durante una ventana configurable para que cada consumidor los procese a su ritmo y se recupere ante fallas.

**Funcionalidad 2: Motor de Asignación Automática de Pedidos**
La plataforma mantendrá un índice de repartidores disponibles y, ante cada pedido, seleccionará al más conveniente según distancia, carga actual y tiempo de preparación del comercio. Ante un rechazo o demora, el pedido será reevaluado automáticamente.

**Funcionalidad 3: Seguimiento en Vivo del Envío**
El cliente podrá ver la posición del repartidor asignado a medida que se actualiza, sin necesidad de consultas periódicas. El último estado de cada envío se conservará para reconstruir la vista ante una reconexión.

**Funcionalidad 4: Escalado Automático Según la Curva de Demanda**
El sistema combinará políticas de escalado programado, que anticipan las franjas de mayor actividad, con políticas reactivas según la carga observada. Fuera de los picos, la infraestructura se contraerá hasta un mínimo operativo.

**Funcionalidad 5: Historial de Recorridos y Panel Analítico**
Los eventos de posición y del ciclo de vida de los pedidos se archivarán de forma continua, con traslado automático de lo más antiguo a almacenamiento de menor costo, permitiendo analizar tiempos de entrega, cobertura y desempeño de la flota.

---

## 2. Plataforma de Comercio Electrónico Elástica para Eventos de Demanda Estacional

Se propone una plataforma de comercio electrónico en la nube que absorbe los picos de tráfico de fechas como Black Friday y Cyber Monday mediante escalado automático, balanceo de carga y despliegue distribuido, reduciendo su costo al normalizarse la demanda.

### 2.2. Introducción y Contexto Detallado

Las tiendas en línea de comercios minoristas medianos operan casi todo el año con un tráfico estable, pero concentran buena parte de su facturación en unas pocas fechas comerciales, durante las cuales el tráfico puede multiplicarse por veinte o treinta y volver a la normalidad al día siguiente. Al funcionar sobre servidores de capacidad fija dimensionados para el pico histórico, sostienen todo el año una capacidad que aprovechan pocos días y que, aun así, no garantiza soportar el evento.

### 2.3. Justificación de la Necesidad y Ventaja Estratégica Cloud

La elasticidad es el argumento central, el pico supera en un orden de magnitud la línea base y dura pocos días al año, por lo que el pago por uso convierte una inversión fija en un costo variable proporcional al tráfico. El escalado horizontal automático y el balanceo de carga permiten incorporar capacidad sin interrumpir el servicio, algo determinante porque una degradación durante la promoción no difiere la venta sino que la pierde. El despliegue en múltiples zonas aporta además la tolerancia a fallos que un servidor dedicado no ofrece.

### 2.4. Propuesta de Solución en la Nube

La plataforma se despliega en capas, la aplicación corre en instancias sin estado bajo escalado automático, distribuidas en varias zonas detrás de un balanceador de carga. El contenido estático se sirve desde una red de distribución, la capa de datos se apoya en un servicio gestionado con réplicas de lectura y caché, y la confirmación de compra se desacopla mediante colas de mensajes.

### 2.5. Funcionalidades Clave

**Funcionalidad 1: Catálogo y Navegación con Entrega Acelerada de Contenido** — Imágenes y recursos desde una red de distribución con puntos de presencia regionales; consultas de catálogo frecuentes desde caché y réplicas de lectura.

**Funcionalidad 2: Escalado Automático de la Capa de Aplicación** — Instancias sin estado en al menos dos zonas de disponibilidad, detrás de un balanceador con health checks, escalando según la carga observada.

**Funcionalidad 3: Proceso de Compra Desacoplado** — La orden se registra en una cola; pago, reserva y notificaciones se procesan de forma asíncrona.

**Funcionalidad 4: Control de Admisión ante Saturación** — Al superar un umbral de concurrencia, los usuarios entrantes pasan a una sala de espera y se habilitan progresivamente.

**Funcionalidad 5: Monitoreo del Evento y Control de Costos** — Pruebas de carga previas a cada campaña; panel de métricas con alertas durante el evento; etiquetado de recursos para atribuir el gasto por campaña.
