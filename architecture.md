# Architecture — Kong AI Fraud Detection Platform

## Logical Architecture

```
+----------------------+    +----------------------+    +----------------------+
|   Mobile Apps        |    |   Fintech Partners   |    | Internal Analytics   |
+----------------------+    +----------------------+    +----------------------+
           |                           |                           |
           +---------------------------+---------------------------+
                                       |
                          (Demo: kubectl port-forward :8000)
                          (Prod:  AWS NLB  →  kong-proxy svc)
                                       |
                                       v
+-----------------------------  AWS EKS Cluster  ------------------------------+
|                                                                              |
|  Namespace: kong                                                             |
|  +======================+                                                    |
|  |      Kong Gateway    |                                                    |
|  |----------------------|                                                    |
|  | • OAuth / OIDC       |                                                    |
|  | • mTLS               |                                                    |
|  | • Rate Limiting      |                                                    |
|  | • Schema Validation  |                                                    |
|  | • PII Redaction      |                                                    |
|  | • AI Governance      |  ◄── connected to Kong Konnect Control Plane       |
|  | • Observability      |      (external SaaS — not on cluster)              |
|  +======================+                                                    |
|              |                                                               |
|   -----------+------------                                                   |
|   |                       |                                                  |
|   v                       v                                                  |
|  Namespace: fintech-services                                                 |
|  +------------------------+    +------------------------+                   |
|  |  Accounts Service      |    | Transactions Service   |                   |
|  | (accounts-service)     |    | (transactions-service) |                   |
|  +------------------------+    +-----------+------------+                   |
|                                            |  (mTLS, internal only)         |
|                                            v                                |
|                            Namespace: fraud-api                             |
|                            +------------------------+                       |
|                            |     Fraud API          |                       |
|                            | (Internal Service)     |                       |
|                            |------------------------|                       |
|                            | • Feature extraction   |                       |
|                            | • Rules engine         |                       |
|                            | • AI reasoning         |                       |
|                            | • Decision engine      |                       |
|                            +-----------+------------+                       |
|                                        |                                    |
|  Namespace: security                   |                                    |
|  +--------------------+               |                                    |
|  | Keycloak (IdP)     |  ◄── OIDC ────┘  (Kong validates tokens)            |
|  +--------------------+                                                     |
|                                                                              |
|  Namespace: monitoring                                                       |
|  +--------------------+    +--------------------+                           |
|  | Prometheus         |    | Grafana            |                           |
|  +--------------------+    +--------------------+                           |
|                                                                              |
+------------------------------------------------------------------------------+
                                       |
                                       v  (HTTPS — private endpoint)
                            +------------------------+
                            |   LLM Provider         |
                            | (Azure OpenAI / GPT)   |
                            |  – EXTERNAL / PRIVATE –|
                            +------------------------+
```

## Infrastructure Layer (Demo — Minimal)

```
Terraform Cloud (app.terraform.io)
├── Workspace 1: fraud-infra-base  → VPC (2 AZs), EKS cluster, IAM
└── Workspace 2: fraud-infra-app   → Namespaces, Kong DP (Helm),
                                      Keycloak (Helm), kube-prometheus-stack (Helm)

AWS Resources (demo mode)
├── EKS Control Plane               ~$2.40 / day
├── Node Group: 2× t3.large Spot    ~$1.00 / day  ← 4 vCPU / 16 GB RAM total
│   (single group, all namespaces)
└── VPC: 2 AZs, 1 shared NAT GW    ~$1.15 / day
                                    ─────────────
                              Total  ~$4.55 / day

Dropped for demo (add back for prod):
  ✗ ECR           — Fraud API not built yet (Phase 6)
  ✗ Secrets Manager + External Secrets Operator — use K8s secrets directly
  ✗ 3rd AZ        — 2 AZs sufficient for demo resilience
  ✗ NLB           — kubectl port-forward covers demo access

Kong Konnect (external SaaS — you already have access)
└── Control Plane: fraud-platform-cp  ◄── Data Plane pods connect via TLS
```

### Node Capacity Check (2× t3.large = 4 vCPU / 16 GB RAM)

| Workload | Namespace | CPU req | RAM req |
|----------|-----------|---------|---------|
| Kong DP (2 replicas) | kong | 500m | 512 Mi |
| accounts-service | fintech-services | 200m | 256 Mi |
| transactions-service | fintech-services | 200m | 256 Mi |
| Keycloak | security | 500m | 512 Mi |
| Prometheus | monitoring | 300m | 512 Mi |
| Grafana | monitoring | 200m | 256 Mi |
| kube-system (DNS, LB ctrl) | kube-system | 300m | 300 Mi |
| **Total** | | **~2.2 vCPU** | **~2.6 GB** |

> Comfortably fits on 2× t3.large with headroom. Scale to t3.xlarge only if Fraud API + LLM workloads are added (Phase 6+).

## Network Policy Matrix

| Source Namespace | Destination Namespace | Allowed | Protocol |
|------------------|-----------------------|---------|----------|
| kong | fintech-services | Yes | HTTPS |
| fintech-services | fraud-api | Yes | mTLS |
| kong | monitoring | Yes | HTTP (scrape) |
| kong | security | Yes | HTTPS (OIDC) |
| * | fraud-api | No (except fintech-services) | — |
| * | security | No (except kong) | — |
