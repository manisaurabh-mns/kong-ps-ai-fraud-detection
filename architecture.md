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
├── Workspace 1: fraud-infra-base    → VPC (2 AZs), EKS cluster, IAM, ECR
├── Workspace 2: fraud-infra-addons  → EKS add-ons, namespaces, Network Policies,
│                                      External Secrets Operator
└── Workspace 3: fraud-infra-app    → Kong DP (Helm), Keycloak (Helm),
                                       kube-prometheus-stack (Helm)

AWS Resources (demo mode)
├── EKS Control Plane
├── Node Group: 3× t3.xlarge Spot  (single group, all namespaces)
├── VPC: 2 AZs, 1 shared NAT Gateway
├── Secrets Manager: Konnect certs, API keys, mTLS certs
└── ECR: Fraud API container image registry

Kong Konnect (external SaaS)
└── Control Plane: fraud-platform-cp  ◄── Data Plane pods connect via TLS
```

## Network Policy Matrix

| Source Namespace | Destination Namespace | Allowed | Protocol |
|------------------|-----------------------|---------|----------|
| kong | fintech-services | Yes | HTTPS |
| fintech-services | fraud-api | Yes | mTLS |
| kong | monitoring | Yes | HTTP (scrape) |
| kong | security | Yes | HTTPS (OIDC) |
| * | fraud-api | No (except fintech-services) | — |
| * | security | No (except kong) | — |
