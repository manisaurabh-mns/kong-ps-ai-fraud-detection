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

## Infrastructure Layer

```
Terraform Cloud (app.terraform.io)
├── Workspace 1: fraud-infra-base  → VPC (2 AZs), EKS cluster, IAM
└── Workspace 2: fraud-infra-app   → Namespaces, Kong DP (Helm),
                                      Keycloak (Helm), kube-prometheus-stack (Helm)

AWS EKS Cluster
├── Node Group: 2× t3.large Spot  (single group, all namespaces)
│   4 vCPU / 16 GB RAM total
└── VPC: 2 AZs, 1 shared NAT Gateway

Kong Konnect (external SaaS — Control Plane)
└── fraud-platform-cp  ◄── Data Plane pods connect via TLS
```

> For instance sizing, cost estimates, and teardown instructions see [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) — Phase 1.

## Network Policy Matrix

| Source Namespace | Destination Namespace | Allowed | Protocol |
|------------------|-----------------------|---------|----------|
| kong | fintech-services | Yes | HTTPS |
| fintech-services | fraud-api | Yes | mTLS |
| kong | monitoring | Yes | HTTP (scrape) |
| kong | security | Yes | HTTPS (OIDC) |
| * | fraud-api | No (except fintech-services) | — |
| * | security | No (except kong) | — |
