# Architecture Defense — Delivery Platform on AWS

Justification of every component: **role**, **configuration and why**, **alternatives ruled out and why**.

- **[LAB]** = ruled out (or forced) by an AWS Academy Learner Lab limitation.
- **WEAKPOINT** = the argument against the alternative is not strong; expect a follow-up question.
- **(unverified)** = Lab availability of that alternative was not tested; check it before claiming it in the defense.
- **(verified 2026-11-18)** = checked on the Learner Lab account: `LabRole` trust policy, `iam simulate-principal-policy` on `LabRole` and `voclabs`, and real read calls. The simulator does not evaluate the Academy SCP, so "allowed" by the simulator alone could still fail on a real create. Full results in [ANALISIS-TP1-LEARNER-LAB.md](ANALISIS-TP1-LEARNER-LAB.md#resultados-de-la-verificación).

## Learner Lab constraints referenced below

| ID | Constraint | Evidence in the repo |
|---|---|---|
| **L1** | Cannot create or modify IAM roles/policies. Every service runs with the pre-existing `LabRole`. | `iam.tf` (`data "aws_iam_role" "lab"`) |
| **L2** | An SCP denies `s3:GetBucketObjectLockConfiguration` and `kinesis:IncreaseStreamRetentionPeriod`, which the Terraform AWS provider always calls. | `recursos-base.tf`, README §4 |
| **L3** | Only `us-east-1` and `us-west-2` are usable. | `variables.tf` (`region` validation) |
| **L4** | Limited credit and sessions that expire; credentials rotate every session. | Budget of 50 USD, secrets refreshed per session |
| **L5** | No access to Billing settings (cost allocation tags) or account governance (Organizations, Control Tower, Config). | `monitoring.tf` (budget comment) |
| **L6** | `LabRole` lacks `xray:PutTraceSegments` and `rds-db:connect`. Consequence of L1. | `modules/lambda_function/main.tf`, `database.tf` |

---

## Quick review table

| Service | Role | Alternative ruled out | Reason |
|---|---|---|---|
| Amazon VPC (2 AZ, 2 private tiers, no IGW/NAT) | Network isolation for RDS and the Lambdas that use it | NAT Gateway | ~32 USD/month + per-GB; only 2 AWS APIs are needed from inside the VPC → endpoints are cheaper **[LAB: L4]** |
| VPC Endpoints (Secrets Manager interface, S3 gateway) | Private access to AWS APIs from the VPC | Interface endpoints in both AZs | Halves cost; trade-off is AZ resilience of secret reads — **WEAKPOINT** |
| Security Groups + NACL | Lambda → RDS Proxy:5432 → RDS:5432 and Lambda/proxy → endpoints:443 only | Only SGs (no NACL) | Defense in depth; NACL is redundant with SGs — **WEAKPOINT** (low cost, low value) |
| Amazon RDS for PostgreSQL 16 + PostGIS | System of record + geospatial "nearest driver" query | DynamoDB | No geospatial index/`ORDER BY distance`, no relational constraints |
| | | Aurora (provisioned / Serverless v2) | Higher minimum cost for a tiny workload **[LAB: L4]** — **WEAKPOINT** for Serverless v2 |
| Amazon RDS Proxy | Connection pool between the scaling Lambdas and `db.t3.micro` | Reserved concurrency on the VPC Lambdas | Caps throughput instead of sharing connections; one cap per function, hard to size |
| | | Per-container connections only (previous design) | A burst of containers exhausts the ~100 connections of `db.t3.micro` |
| AWS Secrets Manager | DB credentials | SSM Parameter Store SecureString | Free and also works — **WEAKPOINT**; Secrets Manager is the RDS-native option for rotation, but rotation is not enabled |
| Amazon Cognito User Pool | Authentication, roles via groups | Identity Pools | Need IAM roles for authenticated users **[LAB: L1]**; not needed (presigned POST) |
| | | Self sign-up | Anyone could register as a driver |
| API Gateway HTTP API + JWT authorizer | Single HTTPS entry point, token validation | REST API | ~3.5× price, higher latency, JWT needs Lambda/Cognito authorizer; loses request validation/WAF/caching — **WEAKPOINT** |
| | | Lambda authorizer | Extra code, latency and cost for what the native JWT authorizer does |
| | | API Gateway WebSocket API | Frontend polls instead — **WEAKPOINT** (no Lab reason) |
| AWS Lambda (Python 3.12, 19 functions, 3 layers) | All compute | ECS Fargate / EC2 | Always-on cost and ops for spiky, low traffic **[LAB: L4]** |
| | | Lambda in VPC for everything | Only RDS clients go in the VPC; the rest would need NAT/endpoints |
| Amazon SQS FIFO (+ DLQ) | Buffer between the API and the order workflow | SQS Standard | Dedup by `pedido_id`; but dedup is also enforced by the execution name — **WEAKPOINT** |
| | | API Gateway → Step Functions direct integration | Loses validation and buffering. Not blocked by L1: LabRole works as credentials role (verified 2026-11-18) |
| | | EventBridge Pipes (SQS → SFN) | Not blocked by L1: `pipes.amazonaws.com` can assume LabRole (verified 2026-11-18); would remove `iniciar-proceso` — **WEAKPOINT** |
| AWS Step Functions (Standard ×2) | Order assignment and delivery confirmation workflows | Express workflows | 5-minute limit and no `.waitForTaskToken` |
| | | Choreography with Lambdas + SQS | Timeouts, retries and state would be hand-written |
| Amazon SNS (`estado-pedido`) | Order-state event fan-out | EventBridge | Comparable — **WEAKPOINT**; SNS is direct and native to Step Functions |
| | | Notifications delivered to users | Subscriber only logs — **WEAKPOINT** |
| Kinesis Data Streams (1–4 shards, provisioned) | Ingest of driver GPS positions, 2 consumers | SQS | One consumer per message, no replay, no per-key ordering across consumers |
| | | Direct writes to RDS | One DB write per GPS ping; Kinesis batches and keeps the last position |
| | | On-demand capacity | ~3× the price of 1 shard at this volume **[LAB: L4]**; allowed in the Lab (verified 2026-11-18) |
| Lambda `escalar-capacidad` + EventBridge Scheduler + alarm | Scheduled (lunch/dinner) and reactive (throttled writes) stream scaling | Lambda provisioned concurrency / Application Auto Scaling | Explicit deny / service-linked role cannot be created **[LAB: L1]** (verified 2026-11-18) |
| | | Scaling RDS on a schedule | Instance class change = downtime; RDS is not the ingest bottleneck |
| | | Data Firehose to S3 | Not blocked by L1: `firehose.amazonaws.com` can assume LabRole (verified 2026-11-18) — **WEAKPOINT** |
| Amazon S3 (`comprobantes`, `historico`) | Delivery proof photos / position and order-event history | One bucket with prefixes (previous design) | Lifecycle, CORS and endpoint policy had to be scoped by prefix; mixed operational and analytical data |
| | | Upload through API Gateway/Lambda | Payload limits, pays Lambda time for bytes |
| | | Presigned PUT | Cannot enforce max size |
| | | SSE-KMS | KMS request cost; no access-control gain with one role **[LAB: L1]** |
| Lambda `recursos-base` (custom resource) | Creates the buckets and stream | `aws_s3_bucket` / `aws_kinesis_stream` | Provider calls denied by SCP **[LAB: L2]** |
| CloudWatch (logs, dashboard, alarms) | Observability | X-Ray | **[LAB: L6]** |
| SNS `alertas` + email | Alarm/budget delivery | Encrypted topic | Alarms cannot publish to `aws/sns`-encrypted topics; CMK needs custom key policy |
| AWS Budgets | Cost control | Tag-filtered budget | Requires cost allocation tags in Billing **[LAB: L5]** |
| AWS Backup | Daily RDS copy that outlives the instance | Only RDS automated backups | Deleted with the instance; cannot be copied cross-region/account |
| CloudTrail (event history) | Audit | Dedicated trail | Needs another S3 bucket, created outside the provider **[LAB: L2]** — **WEAKPOINT** |
| IAM (`LabRole`) | Execution identity for everything | Least-privilege role per function | **[LAB: L1]** |
| Terraform + S3 remote state (native lock) | IaC and deployment | DynamoDB lock table | Deprecated; one less resource |
| | | GitHub OIDC role | Needs IAM OIDC provider + role **[LAB: L1]** |
| AWS Amplify Hosting | Client and driver UIs over HTTPS | S3 + CloudFront | CloudFront denied in the Lab **[LAB]** (verified 2026-11-18) |
| | | S3 static website alone | HTTP only: no `crypto.randomUUID` or geolocation in the browser; needs a public bucket |
| | | Local Vite dev server (previous design) | Not hosted on AWS; kept only for development |

---

## 1. Networking

### Amazon VPC

**Role.** Places RDS in private subnets with no route to the Internet and gives the Lambdas that talk to RDS a private network path.

**Configuration and why.**
- `10.0.0.0/16`, **2 AZs** (`slice` of the available ones): an RDS DB subnet group requires subnets in at least 2 AZs (enforced with a `precondition`), and it enables Multi-AZ later without network changes.
- **Two private tiers**: `app` (`10.0.10.0/24`, `10.0.11.0/24`) for VPC Lambdas and RDS Proxy, `datos` (`10.0.20.0/24`, `10.0.21.0/24`) for RDS. Separating tiers allows a dedicated NACL on the data tier.
- **No Internet Gateway, no NAT** (`create_igw = false`, `enable_nat_gateway = false`): nothing in the VPC needs the Internet. The database is unreachable from outside by construction, not only by configuration.
- Built with the community module `terraform-aws-modules/vpc/aws`: subnets, route tables, DB subnet group and NACLs in one tested module.

**Alternatives ruled out.**
- **NAT Gateway**: ~0.045 USD/h (~32 USD/month) plus per-GB processing, for a VPC that only needs Secrets Manager and S3. **[LAB: L4]** It would consume most of the Lab credit.
- **Public subnets / publicly accessible RDS**: exposes the database; no requirement justifies it.
- **Single AZ**: not allowed by the RDS subnet group and blocks Multi-AZ.

### VPC Endpoints

**Role.** Let the VPC Lambdas (and RDS Proxy, if it reads the secret from its VPC interfaces) reach Secrets Manager and S3 (`marcar-entregado` checks the proof photo; `archivar-eventos` writes order events) without NAT.

**Configuration and why.**
- **Secrets Manager — interface endpoint** with private DNS, so the SDK uses the normal hostname. Placed in **one AZ by default** (`endpoint_una_az = true`): each AZ costs ~7.3 USD/month.
- **S3 — gateway endpoint** (free), attached to the private route tables, with an **endpoint policy** that allows only `GetObject`/`ListBucket` on the `comprobantes` bucket and `PutObject` on `pedidos/*` of the `historico` bucket. A compromised VPC Lambda cannot exfiltrate to other buckets.
- Only these two: the Lambdas that call SQS, Kinesis or Step Functions run **outside** the VPC, so no endpoints are needed for them.

**Alternatives ruled out.**
- **NAT Gateway**: see VPC.
- **Interface endpoint in both AZs**: doubles the cost. **WEAKPOINT**: if that AZ fails, VPC Lambdas in the other AZ cannot read the secret on cold start. The flag exists to turn it on for production.
- **S3 interface endpoint**: costs per hour; the gateway endpoint is free and sufficient.

### Security Groups and NACL

**Role.** Restrict traffic to exactly two flows.

**Configuration and why.**
- SGs reference each other instead of CIDRs: `lambda → rds:5432`, `lambda → vpce:443`, `lambda → S3 prefix list:443`. Only resources in the Lambda SG can reach RDS, regardless of IP.
- `create_before_destroy` on SGs: a replacement never leaves resources without rules.
- **NACL on the data tier**, generated with a `for` over the app subnets: inbound only 5432 from app subnets, outbound only ephemeral ports to them.

**Alternatives ruled out.**
- **SGs only**: would be enough. **WEAKPOINT**: the NACL is defense in depth (stateless, subnet-level) with no cost, but it adds no protection the SGs do not already give unless an SG is misconfigured.

---

## 2. Data

### Amazon RDS for PostgreSQL + PostGIS

**Role.** System of record: shops, products, orders, drivers, last known position, assignments, ratings. Executes the **nearest available driver** query.

**Configuration and why.**
- **PostgreSQL 16 with PostGIS**: `geography(Point)` columns with a **GiST index**; `ST_DWithin` filters by radius and `ORDER BY <->` returns the nearest driver using the index.
- **Constraints enforce business rules** that would otherwise need distributed locking: partial unique index `pedido_un_asignado` (a driver cannot have two assigned orders), `asignacion_una_pendiente` (one pending offer per driver), `CHECK` on states.
- **`db.t3.micro`, 20 GB gp3**: smallest class for a demo workload; gp3 gives baseline IOPS independent of size and is cheaper than gp2. **[LAB: L4]**
- **`storage_encrypted = true`**, **`publicly_accessible = false`**, in the `datos` subnets; its security group only accepts 5432 from RDS Proxy.
- **TLS enforced from the client**: the Lambdas connect to RDS Proxy (`require_tls`), whose certificate is issued by Amazon Trust Services, so `db.py` trusts the system CAs; the RDS CA bundle (downloaded at plan time with a `postcondition`, shipped as a layer) is also trusted for direct connections. `pg8000` verifies the server certificate.
- **`multi_az = false` by default** (variable): Multi-AZ doubles the instance cost. Turned on for production; `db.py` reconnects after a failover.
- **Backups 7 days** (`db_dias_backup`): point-in-time restore with ~5 min RPO.
- **`deletion_protection = false`, `skip_final_snapshot = true`**: the pipeline `destroy` must remove everything unattended (course requirement). In production both would be inverted.
- **Password auth from Secrets Manager**, not IAM auth: **[LAB: L6]** `rds-db:connect` cannot be granted to LabRole.
- **Performance Insights off**: not available for `db.t3.micro`.
- Connection reuse: one connection cached per Lambda container (`db.py`) to RDS Proxy, discarded and reopened on `InterfaceError`/`OSError`.

**Alternatives ruled out.**
- **DynamoDB**: no native geospatial index or distance ordering (would require geohash schemes and client-side filtering), and no cross-item constraints like "one assigned order per driver" without conditional-write choreography. The data is relational (orders ↔ items ↔ products ↔ shops).
- **Aurora PostgreSQL (provisioned)**: also supports PostGIS, but the smallest instance is larger and more expensive than `db.t3.micro`. **[LAB: L4]**
- **Aurora Serverless v2**: minimum capacity billed continuously unless scaled to 0; more expensive and more complex for a demo. **WEAKPOINT**: it would scale the database itself; the argument is cost, not capability. Lambda connection bursts are already handled by RDS Proxy.

### Amazon RDS Proxy

**Role.** Connection pool between the Lambdas and the database. Each Lambda container opens its own connection; under a burst, hundreds of containers would exhaust the ~100 connections of `db.t3.micro`. The proxy multiplexes client connections over a small pool, returning the backend connection at the end of each transaction.

**Configuration and why.**
- **Auth with the existing Secrets Manager secret**, assumed through **LabRole** (`rds.amazonaws.com` is in its trust policy; `CreateDBProxy` allowed — verified 2026-11-18, and a proxy with a target was created end to end on 2026-11-20). `iam_auth = DISABLED` for the same reason as the instance **[LAB: L6]**.
- **`require_tls = true`**; the Lambdas read user/password from the secret and connect to `DB_HOST` (the proxy endpoint).
- **In the `app` subnets**, next to the Lambdas and the Secrets Manager endpoint; the `datos` NACL already allows 5432 from those subnets, so the data tier is unchanged. The proxy SG may reach the endpoint on 443 in case the secret is read from the VPC (there is no NAT).
- **Pool**: `max_connections_percent = 90` (`db_proxy_max_conexiones_pct`) leaves room for an emergency direct connection; `connection_borrow_timeout = 30 s` makes a Lambda wait for a free connection instead of failing.
- **No pinning**: the code issues no session `SET`, named `PREPARE` or temp tables; `pg8000` uses unnamed statements.
- **Failover**: clients stay connected to the proxy, which tracks the new primary without waiting for DNS propagation.
- **Migration**: `migrar-esquema` retries while the target goes from registering to `AVAILABLE` (a few minutes after the proxy itself is available).

**Alternatives ruled out.**
- **Reserved concurrency on the VPC Lambdas**: caps throughput rather than sharing connections, one number per function that is hard to size; requests beyond the cap are throttled.
- **Per-container connections only** (previous design): no protection against bursts.
- **Cost**: billed per vCPU of the instance with a 2-vCPU minimum, ~0.03 USD/h. **[LAB: L4]** Accepted: it was the main scaling WEAKPOINT.
- **ElastiCache (Redis GEO) for live positions**: a second datastore to operate and pay for; the nearest-driver query must join positions with availability and pending assignments, which lives in PostgreSQL.

### AWS Secrets Manager

**Role.** Stores DB host, port, user and password; read by VPC Lambdas through the interface endpoint.

**Configuration and why.**
- Password generated by `random_password` (32 chars), written once by Terraform.
- Encrypted with the AWS managed key `aws/secretsmanager`: a CMK adds no access control when every principal is LabRole. **[LAB: L1]**
- `recovery_window_in_days = 0`: allows destroy + re-apply with the same name in the same Lab session.

**Alternatives ruled out.**
- **SSM Parameter Store SecureString**: free tier, would work equally well, and also needs an interface endpoint. **WEAKPOINT**: the real advantage of Secrets Manager is native rotation for RDS, and rotation is **not** configured. Answer: it is the service designed for DB credentials and enables rotation without code changes.
- **Environment variables with the password**: visible in the Lambda console and in Terraform plan output.
- **RDS-managed master password** (`manage_master_user_password`): **WEAKPOINT**, it would create and rotate the secret automatically; not used, no Lab reason identified.

---

## 3. Identity and API

### Amazon Cognito User Pool

**Role.** Authenticates customers and drivers and issues JWTs; groups define the role.

**Configuration and why.**
- **Email as username**, auto-verified, recovery by verified email.
- **Password policy**: 8+ chars, upper, lower, numbers.
- **`allow_admin_create_user_only = true`**: no self sign-up. Role = group; if users could register, anyone could become a driver.
- **Groups `cliente` and `repartidor`**: emitted in the `cognito:groups` claim; each Lambda checks it (`api.grupos`).
- **One app client per role**, **no client secret** (a browser SPA cannot keep one), **SRP** login (the password never travels), refresh tokens, `ADMIN_USER_PASSWORD_AUTH` only for the smoke test (requires IAM credentials, unusable from a browser).
- **`prevent_user_existence_errors`**: login does not reveal whether an email exists.
- Demo users created by Terraform with random passwords, kept only in state.

**Alternatives ruled out.**
- **Cognito Identity Pools** (temporary AWS credentials in the browser to upload to S3): require IAM roles for authenticated identities. **[LAB: L1]** Also unnecessary: presigned POST covers the only direct-to-AWS call.
- **Self sign-up with group by app client**: privilege escalation (see above).
- **Custom auth in Lambda + table of users**: reimplements hashing, tokens and recovery.

### Amazon API Gateway (HTTP API)

**Role.** Single HTTPS entry point; validates JWTs, applies CORS and throttling, routes to Lambdas.

**Configuration and why.**
- **HTTP API** with **native JWT authorizer**: issuer = the User Pool, audience = both app client IDs. Invalid tokens are rejected before invoking (and paying for) a Lambda. Every route requires it.
- **CORS handled by API Gateway**: preflight `OPTIONS` answered without authorizer or Lambda; origins come from a validated variable (no wildcards).
- **Throttling 50 rps / burst 100** on the stage: protects RDS (small instance) from floods.
- **JSON access logs** (request ID, IP, route, status, latency, user `sub`, integration error) with **7-day retention**.
- `$default` stage with `auto_deploy`; `AWS_PROXY` integrations with payload v2.0; one integration per Lambda, 12 routes generated with `for_each`.

**Alternatives ruled out.**
- **REST API**: ~3.5 USD vs 1 USD per million requests and higher latency; JWT validation would need a Cognito authorizer (works) or a Lambda authorizer. **WEAKPOINT**: REST adds request validation, usage plans, caching and WAF integration, which HTTP API lacks. Answer: validation is done in the Lambdas, and none of the others is needed at this scale.
- **Lambda authorizer**: extra function, latency and cost for what the JWT authorizer does natively.
- **Lambda Function URLs**: no centralized auth, CORS, throttling or routing; 8 public URLs instead of one API.
- **Per-route authorization by scopes**: authorization by group is done in code. **WEAKPOINT**: a route-level check would reject wrong-role requests before invoking the Lambda; needs access-token scopes defined on a resource server.
- **WebSocket API for real-time order state / offers**: the frontend polls (4–15 s). **WEAKPOINT**: no Lab reason; WebSocket would cut latency and requests, at the cost of a connection table and a push Lambda.

---

## 4. Compute

### AWS Lambda

**Role.** All business logic: 8 API handlers, 5 workflow tasks, 2 stream consumers, 1 queue consumer, 1 SNS subscriber, plus `migrar-esquema` and `recursos-base` for provisioning.

**Configuration and why.**
- **Own Terraform module** `lambda_function` (used 19 times): zip, log group with **7-day retention**, function, optional VPC config and env vars. Consistency and short declarations.
- **Python 3.12**, `pg8000` (pure Python, no native build needed).
- **Layers**: `db` (driver + `db.py`), `api` (response/claims helpers), `rds-ca` (CA bundle). Shared code without copying it into 19 zips.
- **VPC only for functions that use RDS**. Functions that call SQS, Kinesis, Step Functions or S3 presign run outside the VPC so they reach AWS public endpoints without NAT.
- **Timeouts sized per function**: 10 s default, 15 s for DB-heavy tasks, 30 s for stream consumers, 60 s for migration, 600 s for `recursos-base`.
- **Role: LabRole** **[LAB: L1]**. **No X-Ray** **[LAB: L6]**; tracing replaced by Step Functions execution history + CloudWatch Logs.
- `time_sleep` of 60 s before deleting log groups on destroy: Lambda recreates a deleted log group if it still has logs to flush, which broke the next apply.
- **Schema migration** as a Lambda invoked by Terraform (`aws_lambda_invocation`), re-run when `schema.sql`/`seed.sql` change (`filesha256` trigger): RDS is private, so Terraform cannot connect to it directly.

**Alternatives ruled out.**
- **ECS Fargate / EC2**: always-on cost for traffic that is mostly idle, plus patching/scaling. **[LAB: L4]**
- **All Lambdas in the VPC**: would require endpoints for SQS, Kinesis and Step Functions (~7.3 USD/month each per AZ) or NAT.
- **One monolithic Lambda**: coarser permissions are not an argument here (all LabRole), but separate functions give per-function metrics, timeouts and VPC placement.
- **arm64 (Graviton)**: ~20 % cheaper per GB-s, `pg8000` is pure Python. **WEAKPOINT**: default x86_64 kept with no reason.
- **Memory tuning / reserved concurrency**: defaults used. RDS connections are protected by RDS Proxy instead of capping each function.

---

## 5. Orchestration and messaging

### Amazon SQS FIFO (`pedidos.fifo` + `pedidos-dlq.fifo`)

**Role.** Decouples order intake (`POST /pedidos` → `recibir-pedido`) from processing (`iniciar-proceso` → Step Functions). The API answers `202` immediately.

**Configuration and why.**
- **FIFO with `MessageDeduplicationId = pedido_id`** (client-generated UUID): a retried POST within 5 minutes is dropped by SQS. `MessageGroupId = comercio_id`.
- **SSE with SQS-managed keys**.
- **Visibility timeout 60 s** = 6 × the consumer timeout (10 s), the AWS recommendation for Lambda event sources.
- **`maxReceiveCount = 3` → DLQ** (FIFO, required for a FIFO source), 14-day retention, with a CloudWatch alarm.
- **Batch 10 + `ReportBatchItemFailures`**: only the failed messages and the ones after them are retried, preserving order.
- Second idempotency layer: Step Functions **execution name = `pedido_id`**; `ExecutionAlreadyExists` is ignored.

**Alternatives ruled out.**
- **SQS Standard**: at-least-once and duplicates. **WEAKPOINT**: the execution-name idempotency already absorbs duplicates, and ordering per shop is not a business requirement. FIFO's 300 msg/s limit (without batching / high-throughput mode) is not reached.
- **API Gateway → Step Functions `StartExecution` direct integration**: LabRole can be used as its credentials role (`apigateway.amazonaws.com` is in the trust policy and `iam:PassRole` is allowed — verified 2026-11-18), so the Lab does not block it; it cannot validate the body or inject `cliente_id` from the token, and gives no buffer against `StartExecution` throttling.
- **EventBridge Pipes (SQS → Step Functions)**: would remove `iniciar-proceso`. LabRole can be assumed by `pipes.amazonaws.com` and `pipes:CreatePipe` is allowed (verified 2026-11-18), so the Lab does not block it. **WEAKPOINT**: the only argument left is keeping one more Lambda in exchange for familiar code and logs.

### AWS Step Functions (Standard)

**Role.** Two workflows. `procesar-pedido`: create order → notify → find nearest driver → offer and wait for answer → assign, retry with another driver, or cancel. `confirmar-entrega`: verify photo in S3 → mark delivered → notify.

**Configuration and why.**
- **Standard type**: the workflow waits for a human (up to `asignacion_timeout_segundos` = 60 s per offer) and retries "no drivers nearby" for up to 300 s, several times per order.
- **`.waitForTaskToken`**: `ofrecer-pedido` stores the token in RDS; the driver's accept/reject (`responder-asignacion`) calls `SendTaskSuccess`/`SendTaskFailure`. `TimeoutSeconds` expires the offer without any timer code.
- **Retries declared in ASL**: Lambda transient errors (3 attempts, backoff ×2); `SinCandidatos` every 15 s until the wait window ends; `SinComprobante` 3 times (photo upload may still be in progress).
- **`Catch` → compensating states** (`Rechazada`, `Vencida`, `Cancelar`), with a `Choice` that loops back to `BuscarRepartidor`.
- **Direct `sns:publish` integration**: no Lambda just to publish; a failure to notify does not fail the order.
- ASL generated with `templatefile`: ARNs and timing values injected from variables.
- Role: LabRole **[LAB: L1]**.

**Alternatives ruled out.**
- **Express workflows**: max 5-minute duration and **no `.waitForTaskToken`** support. Both are required.
- **Choreography (Lambdas + SQS delay queues + DB timers)**: timeouts, retries and state transitions would be hand-written and invisible; Standard gives a per-order execution history used for tracing (replacing X-Ray).

### Amazon SNS (`estado-pedido`)

**Role.** Publishes order state changes (created, assigned, cancelled, delivered, rejected) for any number of subscribers.

**Configuration and why.**
- Encrypted with `alias/aws/sns`: only Step Functions and LabRole publish, both authorized by the managed key; a CMK changes nothing about who can read. **[LAB: L1]**
- Subscriber: `notificar` Lambda (permission scoped to the topic ARN).

**Alternatives ruled out.**
- **EventBridge**: content-based routing and archive/replay. **WEAKPOINT**: equally valid; SNS chosen for simple fan-out and native Step Functions integration.
- **Calling a notification Lambda directly from Step Functions**: couples the workflow to each consumer.
- **WEAKPOINT**: `notificar` only logs. Users learn of state changes by polling the API. Email/SMS/push subscribers are the intended extension (SMS in SNS sandbox requires verified numbers).

---

## 6. Real-time positions

### Amazon Kinesis Data Streams (`posiciones`)

**Role.** Ingests driver GPS pings (`PUT /repartidores/me/posicion` → `registrar-posicion`) and feeds two independent consumers: `actualizar-posicion` (last position in RDS) and `archivar-posiciones` (history in S3).

**Configuration and why.**
- **1 shard, provisioned**: 1 MB/s or 1,000 records/s of writes; at one ping every few seconds per driver this supports hundreds of drivers. ~11 USD/month. **[LAB: L4]**
- **Partition key = driver ID** (taken from the token, never the body): all pings of a driver go to the same shard, in order.
- **KMS encryption with `aws/kinesis`**.
- **24 h retention (default)**: cannot be increased **[LAB: L2]**.
- Created by `recursos-base`, not by Terraform: **[LAB: L2]** the provider's create call is denied by the SCP and leaves the stream half-created.
- `ProvisionedThroughputExceeded` → 503; the app sends the next position anyway.
- **Two event source mappings with different settings**:

| Setting | `actualizar-posicion` | `archivar-posiciones` | Why |
|---|---|---|---|
| Starting position | `LATEST` | `TRIM_HORIZON` | Old positions are useless for assignment; the archive must not lose any |
| Batch / window | 100 / 1 s | 1000 / 60 s | Low latency vs. fewer, larger S3 objects |
| Max record age | 300 s | unlimited | A 5-min-old position is discarded; archive keeps everything |
| Errors | bisect, 3 retries, on-failure → SQS `posiciones-fallidas` | same | A poison record does not block the shard; failed ranges can be re-read within retention |

- `actualizar-posicion` keeps only the newest ping per driver per batch and upserts with `WHERE actualizado_en < EXCLUDED.actualizado_en`: one DB write per driver per second at most, and out-of-order records cannot overwrite newer ones.

**Alternatives ruled out.**
- **SQS**: a message is consumed by one consumer only (two queues + SNS fan-out would be needed), no replay, and ordering per driver only with FIFO.
- **Writing every ping directly to RDS**: one transaction per ping on a `db.t3.micro`; Kinesis absorbs bursts and lets the consumer collapse them.
- **On-demand capacity**: per-stream hourly charge (~0.04 USD/h) plus per-GB, ~3× one shard at this volume. **[LAB: L4]**
- **Data Firehose** for the S3 archive (instead of `archivar-posiciones`): buffering and delivery without code. Requires a delivery role; LabRole can be assumed by `firehose.amazonaws.com` and `firehose:CreateDeliveryStream` is allowed (verified 2026-11-18), so the Lab does not block it. **WEAKPOINT**: Firehose is the better tool here; switching to it is recommended, or the defense must argue the custom batching/keys of `archivar-posiciones`.
- **Enhanced fan-out**: dedicated 2 MB/s per consumer at extra cost; 2 consumers fit in the shared 2 MB/s read throughput.

### Stream scaling (`escalar-capacidad`)

**Role.** Implements TP1 feature 4 (scaling following the demand curve) on the only fixed-capacity piece of the ingest path: the shard count of `posiciones`. Lambda, Step Functions and API Gateway already scale on their own and drop to zero.

**Configuration and why.**
- **Scheduled**: EventBridge Scheduler, cron in `America/Argentina/Buenos_Aires`. Each window (lunch, dinner) has a start schedule (`pico` → `shards_pico`) and an end schedule (`base` → one halving step towards `shards_minimo`) that fires three times, one hour apart, because Kinesis halves at most once per call.
- **Reactive**: CloudWatch alarm on `WriteProvisionedThroughputExceeded` (Sum > 0 in 2 of 3 one-minute periods) with a **Lambda alarm action** (`subir` → double, up to `shards_maximo`). An alarm only acts on a state change, so after scaling the Lambda **re-arms it** (`SetAlarmState` → OK) to let it fire again if the new capacity is not enough. A **5-minute cooldown** (timestamp kept in the alarm's state reason, read back from `previousState`) prevents doubling again on the throttles still inside the 3-minute window. No SNS action on the alarm (it would email every minute while re-arming); the Lambda notifies `alertas` on every shard change.
- **One Lambda for both**, reserved concurrency **1**: two `UpdateShardCount` calls on the same stream would conflict. It is idempotent (no call if the target equals the current count, `pico` never scales down), raises `StreamOcupado` while the stream is `UPDATING` so Scheduler (5 retries) or async invocation (2 retries) retries, and publishes to `alertas` instead of failing when the daily quota is exhausted.
- **Kinesis limits drive the defaults (1 / 2 / 4)**: each call can at most double or halve, and a stream allows **10 resharding operations per rolling 24 h**. Validations enforce `pico ≤ 2 × minimo` and `maximo ≤ 2 × pico`; worst day = 8 operations.
- Shard count published as an EMF metric (`delivery/Escalado` → `Shards`), shown in the dashboard next to throttled writes.
- Scheduler uses **LabRole** as its execution role (`scheduler.amazonaws.com` is in its trust policy).
- **Tested in the Lab (2026-11-18)**: scheduled `pico`/`base` 1 → 2 → 1; a burst of ~1,200 records/s on 1 shard fired the alarm, the Lambda scaled 1 → 2 and re-armed it; the alarm fired twice more on the old throttles and the cooldown skipped both; with 2 shards throttling dropped to 0. Consumers kept reading the child shards (archive objects from `shardId-000000000003`).

**Alternatives ruled out.**
- **Lambda provisioned concurrency on a schedule (Application Auto Scaling)**: `PutProvisionedConcurrencyConfig` has an explicit deny and the Application Auto Scaling service-linked role cannot be created **[LAB: L1]** (verified 2026-11-18). It would also only remove cold starts; Lambda already scales.
- **Kinesis on-demand**: scales by itself and would cover the reactive part, but costs ~3× one shard at this volume **[LAB: L4]** and has no scheduled component. Allowed in the Lab (verified 2026-11-18).
- **EventBridge rules instead of Scheduler**: need no role, but cron only in UTC and no retry policy per target.
- **Scaling on `IncomingRecords`**: capacity changes with the shard count, so a fixed threshold is wrong after scaling; throttled writes are the direct signal of missing capacity.
- **Scaling RDS on a schedule**: changing the instance class restarts the instance (minutes of downtime, Multi-AZ only shortens it to a failover), the ingest path does not depend on RDS capacity (`actualizar-posicion` collapses each batch to one write per driver), and the scalable alternative (Aurora Serverless v2) is a cost decision, not a scaling policy. Connection bursts are absorbed by RDS Proxy. **WEAKPOINT**: under sustained heavy load the instance CPU is the limit; the answer is a larger class or Aurora Serverless v2.

---

## 7. Storage

### Amazon S3 (`comprobantes` and `historico` buckets)

**Role.** Two buckets, one use each:
- **`comprobantes`**: delivery proof photos (operational data). Written by the browser, read by `marcar-entregado`.
- **`historico`**: `posiciones/` and `pedidos/` (JSON Lines partitioned by date, read by Athena) and `athena/` (query results).

**Why two buckets.** They differ in writer, reader, retention and permissions. Separate buckets give each its own configuration (CORS only on `comprobantes`, the Glacier IR lifecycle only on `historico`) and let the VPC endpoint policy grant read on one bucket and write on one prefix of the other, instead of scoping everything by prefix inside a shared bucket. Both are created by `recursos-base` at no extra cost.

**Configuration and why.**
- **Direct browser upload with presigned POST** (`url-comprobante`): key fixed to `<order>/<driver sub>.jpg` in `comprobantes`, conditions `Content-Type = image/jpeg` and `content-length-range 1..5 MB`, expires in 300 s. Bytes never pass through API Gateway/Lambda.
- **CORS on `comprobantes`: POST only**, from the Amplify URL plus `cors_origenes`. The browser can upload but never read or list.
- On both buckets (`for_each`): **Block Public Access** (all four flags) and a **bucket policy denying non-TLS** requests (`aws:SecureTransport = false`).
- **SSE-S3 (AES256)**.
- **Versioning**: an overwritten proof photo can be recovered; noncurrent versions in `historico` expire after 7 days.
- **Lifecycle on `historico`** (`posiciones/` and `pedidos/`; `athena/` expires after 7 days): Standard → **Standard-IA at 30 days** → **Glacier Instant Retrieval at 90 days** → **delete at 180 days**. Variable validated: Standard-IA cannot be before 30 days; days must be increasing.
- **Abort incomplete multipart uploads after 7 days**.
- **Unique names** via `random_id` suffix. Created by `recursos-base` **[LAB: L2]**; all their configuration remains in Terraform.

**Alternatives ruled out.**
- **Upload through API Gateway + Lambda**: payload limits (10 MB API Gateway, 6 MB Lambda sync), base64 overhead, and paying Lambda time to move bytes.
- **Presigned PUT**: cannot enforce a maximum size or content type at S3 level.
- **SSE-KMS**: per-request KMS cost; no access-control benefit when every principal is LabRole. **[LAB: L1]**
- **Glacier Flexible Retrieval / Deep Archive**: retrieval in minutes to hours; Deep Archive's 180-day minimum would be charged in full for data that expires at 180 days. Glacier IR keeps millisecond access for occasional audits; its 90-day minimum is exactly covered (day 90 → 180).
- **Intelligent-Tiering**: per-object monitoring fee; the access pattern (write once, rarely read) is known, so fixed rules are cheaper.
- **DynamoDB / RDS for position history**: append-only, rarely queried data; S3 is far cheaper and analyzable later with Athena.

### Lambda `recursos-base` (custom resource)

**Role.** Creates and deletes the S3 buckets (a map `{comprobantes, historico}`) and the Kinesis stream, invoked by Terraform on create, update **and destroy** (`aws_lambda_invocation` with `lifecycle_scope = "CRUD"`).

**Why it exists.** **[LAB: L2]** The SCP denies `s3:GetBucketObjectLockConfiguration` (every `plan` after the first apply fails for `aws_s3_bucket`) and `kinesis:IncreaseStreamRetentionPeriod` (`aws_kinesis_stream` is left half-created and unencrypted). The Lambda makes only the allowed calls, is idempotent, empties all object versions before deleting the bucket, and returns names/ARNs consumed through `locals`.

**Alternatives ruled out.**
- **Native Terraform resources**: denied **[LAB: L2]**.
- **`local-exec` with the AWS CLI**: depends on the machine running Terraform and is not tied to the destroy lifecycle the same way.
- **CloudFormation stack with a custom resource**: same Lambda, plus a second IaC tool.

---

## 8. Observability, alerts and cost

### Amazon CloudWatch

**Role.** Logs, metrics, operational dashboard and alarms.

**Configuration and why.**
- **Logs**: one log group per Lambda and for API access logs, created by Terraform with **7-day retention** (Lambda would otherwise create them with infinite retention).
- **Dashboard `delivery-operacion`**: workflow executions, API count/4xx/5xx/p90 latency, Lambda errors and throttles (`SEARCH` expression, so new functions appear automatically), Kinesis incoming records and consumer `IteratorAge`, connections Lambdas → proxy vs. proxy → DB and RDS CPU, DLQ depth.
- **Alarms**: any message in `pedidos-dlq` or `posiciones-fallidas` (threshold > 0, also OK notifications), any failed execution per state machine. `treat_missing_data = notBreaching` to avoid false alarms when idle.

**Alternatives ruled out.**
- **X-Ray**: **[LAB: L6]**. Step Functions execution history gives per-order tracing.
- **Alarm on Lambda errors per function**: errors are retried and end in a DLQ or a failed execution, which are already alarmed; avoids duplicate pages.

### Amazon SNS (`alertas`) + email

**Role.** Delivers CloudWatch alarms and budget notifications.

**Configuration and why.**
- **Not encrypted** (tfsec exception): CloudWatch Alarms cannot publish to a topic encrypted with `aws/sns`, and a CMK requires a custom key policy. Content is only alarm names and states.
- **Topic policy** lets the account plus `cloudwatch.amazonaws.com` and `budgets.amazonaws.com` publish, with `aws:SourceAccount` condition.
- Email subscription created only if `alerta_email` is set (`count`).

**Alternatives ruled out.**
- **Reuse `estado-pedido`**: mixes operational alerts with business events and its encryption blocks CloudWatch.

### AWS Budgets

**Role.** Monthly cost limit of 50 USD with alerts at **80 % forecasted** (early warning) and **100 % actual**.

**Alternatives ruled out.**
- **Budget filtered by project tag**: requires activating cost allocation tags in Billing. **[LAB: L5]** The Lab account is used only for this project, so an account-wide budget is equivalent.
- **Cost Anomaly Detection**: not blocked — Cost Explorer reads work and `ce:CreateAnomalyMonitor` is allowed (verified 2026-11-18). **WEAKPOINT**: with a 50 USD budget and daily-granularity anomalies, the budget alerts already cover the risk; anomaly detection needs some history to be useful.

### AWS Backup

**Role.** Daily copy of RDS in a dedicated vault, independent of the instance.

**Configuration and why.**
- Plan `cron(0 6 * * ? *)` (03:00 Buenos Aires, low traffic), start window 60 min, completion 180 min, **retention 7 days**.
- Selection by RDS ARN, using **LabRole** (its trust policy includes `backup.amazonaws.com`; verified in the Lab).
- `force_destroy = true`: the pipeline destroy must succeed with recovery points inside. Production: `false` + Vault Lock.

**Alternatives ruled out.**
- **Only RDS automated backups**: deleted together with the instance and cannot be copied to another region/account (needed for backup & restore / pilot light). They are kept as the PITR layer.
- **Manual snapshots via Lambda/EventBridge**: reimplements scheduling and retention.

### AWS CloudTrail

**Role.** Audit of API calls.

**Configuration and why.** Uses the **default 90-day Event History**, active in every account at no cost.

**Alternatives ruled out.**
- **Dedicated trail to S3**: would need another bucket, which must be created outside the provider **[LAB: L2]**. **WEAKPOINT**: it could be created by `recursos-base` the same way; 90 days of management events is enough for the project.

---

## 9. Identity, IaC and delivery

### IAM (`LabRole`)

**Role.** Execution role for every Lambda, both state machines and AWS Backup.

**Why.** **[LAB: L1]** No other role can be created. Consequence acknowledged in the defense: **no least privilege per function**. Compensating controls: scoped resource policies (Lambda permissions by source ARN, S3 endpoint policy, SNS topic policy, S3 TLS-only policy) and network isolation.

**Alternative ruled out.** One role per function with only its required actions — the correct production design, impossible in the Lab.

### Terraform + remote state in S3

**Role.** All infrastructure as code (162 resources), deployed from GitHub Actions with a smoke test.

**Configuration and why.**
- **State in a private, versioned, SSE-S3 bucket** created by a script with the AWS CLI (it cannot hold its own state, and **[LAB: L2]** blocks `aws_s3_bucket`).
- **Native S3 locking** (`use_lockfile`, Terraform ≥ 1.10) + workflow concurrency queue: no two runs write state at once.
- **Guard against duplicates**: the workflow stops if `delivery` resources exist but the remote state is empty.
- **CI**: `fmt`, `validate`, `plan`, **tfsec** with every exception justified inline, terraform-docs.
- Static Lab credentials as repository secrets, refreshed each session. **[LAB: L4]**

**Alternatives ruled out.**
- **DynamoDB lock table**: deprecated in favor of S3 native locking; one less resource.
- **GitHub OIDC federation**: requires creating an IAM OIDC provider and role. **[LAB: L1]**
- **CloudFormation / CDK**: course uses Terraform; CloudFormation would face the same SCP denials.

### Frontend hosting (AWS Amplify Hosting)

**Role.** React/Vite SPA for customers and drivers, configured from Terraform outputs and served at `https://main.<app>.amplifyapp.com`.

**Configuration and why.**
- **`aws_amplify_app` + `aws_amplify_branch` (`main`, `PRODUCTION`)** in `frontend.tf`. Verified in the Lab on 2026-11-20: Terraform create/refresh/destroy, a manual deployment of the real build, HTTPS, SPA routes.
- **Manual deployment (zip)**, not a connected repository: connecting GitHub needs a personal access token stored in Amplify. `scripts/publicar-frontend.sh` builds with the apply outputs and calls `create-deployment` → upload → `start-deployment`; the deploy workflow runs it after `apply`, and the smoke test checks `/` and `/cliente`.
- **SPA rewrite rule**: every path without a file extension returns `index.html` with 200 (React Router resolves it); missing assets still return 404.
- **HTTPS**: required by the app — `crypto.randomUUID` (idempotent order id) and geolocation only exist in secure contexts.
- **CORS**: the Amplify URL is added in Terraform to the API and `comprobantes` origins; `cors_origenes` keeps `localhost:5173` for development.

**Alternatives ruled out.**
- **S3 + CloudFront**: CloudFront is denied in the Lab (`cloudfront:ListDistributions` → AccessDenied, `CreateDistribution` denied — verified 2026-11-18). **[LAB]**
- **S3 static website alone**: HTTP only, so the app breaks (`crypto.randomUUID` undefined) and geolocation is unavailable; it also requires disabling Block Public Access and a public bucket policy.
- **Local Vite dev server** (previous design): not hosted on AWS; kept only for development.
- **Amazon Location Service** for maps, geocoding and routing (the frontend uses public map/route services): explicitly denied in the Lab (`geo:*` → explicit deny — verified 2026-11-18). **[LAB]**

---

## 10. Region and resilience

- **`us-east-1`** (also allowed `us-west-2`): **[LAB: L3]**.
- Everything except RDS is regional and multi-AZ by default (Lambda, API Gateway, Step Functions, SQS, SNS, Kinesis, S3, Cognito). RDS is the only single-AZ piece; Multi-AZ is one variable away.
- **Warm standby / multi-site** (cross-region replica, Aurora Global Database, Route 53 failover): **[LAB: L3]** effectively one region, plus cost **[LAB: L4]**.
