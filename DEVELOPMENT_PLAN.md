# Development Plan — Kong AI Fraud Detection Platform

> **Project:** Production-grade Fraud Detection & AI Abstraction with Kong Konnect  
> **Audience:** Kong Professional Services, API Architects, Fintech Security Teams  
> **Date:** April 2026

---

## Overview

This plan breaks the build into **9 phases**, progressing from infrastructure bootstrap through
security hardening, fraud logic, AI integration, observability, CI/CD automation, and developer
portal delivery.

```
Phase 1 → Environment & Infrastructure Bootstrap
Phase 2 → Upstream Service Deployment
Phase 3 → Kong Gateway — Core Configuration
Phase 4 → Security & Identity (OAuth / OIDC / mTLS)
Phase 5 → Traffic Governance (Rate Limiting, Caching, Canary)
Phase 6 → Internal Fraud API Build
Phase 7 → AI / LLM Abstraction Layer
Phase 8 → Observability (Prometheus / Grafana)
Phase 9 → CI/CD Automation & Developer Portal
```

---

## Phase 1 — Environment & Infrastructure Bootstrap (AWS EKS + Terraform Cloud)

**Goal:** Production-grade AWS EKS cluster provisioned via Terraform Cloud, Kong Data Plane
running on Kubernetes and connected to Kong Konnect Control Plane, with all services
(upstream APIs, Fraud API, monitoring) deployed on the **same cluster** using namespace isolation.

> **Q: Should all APIs live on the same EKS cluster?**  
> **Yes.** For this architecture, a single EKS cluster with Kubernetes namespace isolation is
> the right call. Kubernetes Network Policies enforce strict service-to-service boundaries
> (e.g. only `fraud-api` namespace can receive traffic from `fintech-services`), and a single
> cluster reduces operational overhead significantly. Separate clusters would only be warranted
> for hard multi-tenancy or compliance separation requirements — neither applies here.

---

### Cluster Namespace Design

```
eks-cluster: kong-fraud-platform
├── kong               → Kong Data Plane pods
├── fintech-services   → accounts-service, transactions-service
├── fraud-api          → Internal Fraud API
├── monitoring         → Prometheus, Grafana
└── security           → Keycloak (Identity Provider)
```

Network Policies enforce:
- `fintech-services` → `fraud-api` (mTLS, internal only)
- `kong` → `fintech-services` (proxy traffic)
- `kong` → `monitoring` scrape (Prometheus)
- No direct consumer access to `fraud-api` or `security` namespaces

---

### Pre-Requisites

#### 1. AWS Account

| Item | Detail |
|------|--------|
| AWS Account | With billing enabled |
| IAM User / Role | `AdministratorAccess` (narrow later to least-privilege) |
| AWS Region | Choose one: `us-east-1` recommended for availability |
| Service Quotas | Verify: EC2 vCPU limit ≥ 32, EIP limit ≥ 5 |

Ensure the following AWS services are accessible in your chosen region:
- EKS, EC2, VPC, IAM, ECR, S3, Route53, ACM, Secrets Manager, CloudWatch

#### 2. Terraform Cloud (app.terraform.io)

| Item | Detail |
|------|--------|
| Account | Sign up at [app.terraform.io](https://app.terraform.io) |
| Organization | Create org: `kong-ps-fraudplatform` |
| Workspaces | 3 workspaces (see workspace plan below) |
| AWS credentials | Add as Workspace Variable Set: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION` (mark sensitive) |
| Terraform version | Pin to `>= 1.7.0` in workspace settings |

#### 3. GitHub Repository

| Item | Detail |
|------|--------|
| Repo | `kong-ps-ai-fraud-detection` (existing) |
| Branch strategy | `main` (protected) → trigger Terraform Cloud VCS runs |
| GitHub Secrets | `TF_API_TOKEN` (Terraform Cloud team API token) for GitHub Actions |
| GitHub Actions | Used for: OAS→Kong conversion, deck sync, Docker image builds (Phase 9) |

Connect Terraform Cloud workspaces to the GitHub repo via **VCS-driven workflow**:
`Settings → Version Control → Connect to GitHub → Select repo → Set working directory per workspace`

#### 4. Local Toolchain (Developer Machine)

```bash
# Required tools
aws --version          # AWS CLI v2.x
terraform --version    # >= 1.7.0
kubectl version        # >= 1.29
helm version           # >= 3.14
deck version           # Kong decK >= 1.38
jq --version           # JSON processor

# Optional but recommended
gh --version           # GitHub CLI
k9s version            # Kubernetes TUI
kubectx / kubens       # Context + namespace switcher
```

Install on macOS:
```bash
brew install awscli terraform kubectl helm jq gh k9s kubectx
brew install kong/deck/deck
```

Install on Linux (Ubuntu):
```bash
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install

# Terraform
sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# decK
curl -sL https://github.com/kong/deck/releases/latest/download/deck_linux_amd64.tar.gz | tar xz
sudo mv deck /usr/local/bin/
```

#### 5. Kong Konnect

| Item | Detail |
|------|--------|
| Account | Sign up / log in at [konghq.com](https://konghq.com) |
| Control Plane | Create a new Control Plane named `fraud-platform-cp` |
| Data Plane certificates | Download `cluster.crt` + `cluster.key` from Konnect UI (used in Helm values) |
| PAT Token | Generate a Personal Access Token under account settings |
| Region | Choose Konnect region matching your AWS region |

---

### Terraform Cloud Workspace Plan

Use **three workspaces** — each maps to a subfolder in `infra/terraform/` in the GitHub repo:

```
Workspace 1: fraud-infra-base
  Working dir: infra/terraform/base/
  Trigger:     changes to infra/terraform/base/**
  Provisions:  VPC, subnets, EKS cluster, IAM roles, ECR, S3 state bucket

Workspace 2: fraud-infra-addons
  Working dir: infra/terraform/addons/
  Trigger:     changes to infra/terraform/addons/**
  Provisions:  EKS add-ons (AWS Load Balancer Controller, EBS CSI Driver, CoreDNS, Kube-proxy)
               Kubernetes namespaces + Network Policies
               AWS Secrets Manager secrets + External Secrets Operator

Workspace 3: fraud-infra-app
  Working dir: infra/terraform/app/
  Trigger:     changes to infra/terraform/app/**
  Provisions:  Kong DP Helm release, Keycloak Helm release,
               kube-prometheus-stack Helm release,
               Kubernetes ConfigMaps + Secrets for services
```

Remote state: Workspace 2 reads outputs from Workspace 1 via `tfe_outputs` data source.
Workspace 3 reads outputs from Workspace 1 and 2.

---

### Terraform Infrastructure Plan

#### Workspace 1 — `fraud-infra-base`

> **Demo mode — minimise cost, destroy when done.**  
> Single NAT Gateway, single node group of Spot instances, no NLB (use `kubectl port-forward`
> for Kong proxy during demo). Entire environment tears down to $0 with one `terraform destroy`.

**VPC (`infra/terraform/base/vpc.tf`)**
```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  name    = "kong-fraud-vpc"
  cidr    = "10.0.0.0/16"
  azs     = ["us-east-1a", "us-east-1b"]   # 2 AZs sufficient for demo
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
  enable_nat_gateway     = true
  single_nat_gateway     = true    # one shared NAT GW — saves ~$65/month vs 3
  one_nat_gateway_per_az = false
  enable_dns_hostnames   = true
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}
```

**EKS Cluster (`infra/terraform/base/eks.tf`)**
```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"
  cluster_name    = "kong-fraud-platform"
  cluster_version = "1.30"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # Single node group — Spot instances cut EC2 cost by ~70%
  eks_managed_node_groups = {
    demo = {
      instance_types  = ["t3.xlarge", "t3a.xlarge"]  # fallback type for Spot availability
      capacity_type   = "SPOT"
      min_size        = 2
      max_size        = 4
      desired_size    = 3     # 3 nodes comfortably runs all workloads
      labels          = { role = "demo" }
      taints          = []    # no taints — all namespaces schedule here
    }
  }
}
```

**Node Group Sizing (Demo):**

| Node Group | Instance | Type | Count | Runs |
|------------|----------|------|-------|------|
| `demo` | t3.xlarge | Spot | 3 | Kong DP + fintech-services + fraud-api + monitoring + Keycloak |

> `t3.xlarge` = 4 vCPU / 16 GB RAM each → 12 vCPU / 48 GB total — enough for all pods.
> Spot interruptions are acceptable for a demo environment.

#### Workspace 2 — `fraud-infra-addons`

Key resources provisioned:
```hcl
# AWS Load Balancer Controller (for Kong's NLB/ALB ingress)
resource "helm_release" "aws_lb_controller" { ... }

# EBS CSI Driver (for Prometheus/Grafana PVCs)
resource "aws_eks_addon" "ebs_csi" { ... }

# External Secrets Operator (sync AWS Secrets Manager → K8s Secrets)
resource "helm_release" "external_secrets" { ... }

# Kubernetes namespaces
resource "kubernetes_namespace" "namespaces" {
  for_each = toset(["kong", "fintech-services", "fraud-api", "monitoring", "security"])
  ...
}

# Network Policies (deny-all default + explicit allow rules)
resource "kubernetes_network_policy" "deny_all" { ... }
resource "kubernetes_network_policy" "allow_kong_to_fintech" { ... }
resource "kubernetes_network_policy" "allow_fintech_to_fraud" { ... }
```

#### Workspace 3 — `fraud-infra-app`

```hcl
# Kong Data Plane via Helm
resource "helm_release" "kong_dp" {
  name       = "kong-dp"
  namespace  = "kong"
  repository = "https://charts.konghq.com"
  chart      = "kong"
  values     = [file("${path.module}/values/kong-dp-values.yaml")]
}

# kube-prometheus-stack (Prometheus + Grafana)
resource "helm_release" "monitoring" {
  name       = "kube-prometheus-stack"
  namespace  = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
}

# Keycloak
resource "helm_release" "keycloak" {
  name       = "keycloak"
  namespace  = "security"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "keycloak"
}
```

---

### Repository Structure for Phase 1

```
kong-ps-ai-fraud-detection/
├── infra/
│   └── terraform/
│       ├── base/                    # Workspace 1: VPC + EKS
│       │   ├── main.tf
│       │   ├── vpc.tf
│       │   ├── eks.tf
│       │   ├── iam.tf
│       │   ├── ecr.tf
│       │   ├── outputs.tf
│       │   └── variables.tf
│       ├── addons/                  # Workspace 2: EKS add-ons + namespaces
│       │   ├── main.tf
│       │   ├── addons.tf
│       │   ├── namespaces.tf
│       │   ├── network_policies.tf
│       │   ├── external_secrets.tf
│       │   └── variables.tf
│       └── app/                     # Workspace 3: Helm releases
│           ├── main.tf
│           ├── kong.tf
│           ├── monitoring.tf
│           ├── keycloak.tf
│           ├── variables.tf
│           └── values/
│               ├── kong-dp-values.yaml
│               ├── prometheus-values.yaml
│               └── keycloak-values.yaml
├── .env.example                     # Template for local env vars
└── DEVELOPMENT_PLAN.md
```

---

### Step-by-Step Setup Instructions

#### Step 1 — Bootstrap GitHub Repo

```bash
cd kong-ps-ai-fraud-detection
git checkout -b infra/phase-1-bootstrap
mkdir -p infra/terraform/{base,addons,app/values}
# Create .gitignore to exclude .terraform/, *.tfstate, *.tfvars (secrets)
cat >> .gitignore << 'EOF'
**/.terraform/
*.tfstate
*.tfstate.backup
*.tfvars
.env
infra/certs/
EOF
git add . && git commit -m "chore: scaffold infra/terraform structure"
git push origin infra/phase-1-bootstrap
```

#### Step 2 — Configure Terraform Cloud

1. Log in to [app.terraform.io](https://app.terraform.io)
2. Create Organization → `kong-ps-fraudplatform`
3. Create **3 workspaces** (Version control workflow → GitHub → select repo):
   - `fraud-infra-base` → working dir: `infra/terraform/base`
   - `fraud-infra-addons` → working dir: `infra/terraform/addons`
   - `fraud-infra-app` → working dir: `infra/terraform/app`
4. In **Organization Settings → Variable Sets** create `aws-credentials`:
   - `AWS_ACCESS_KEY_ID` = `<value>` (env var, sensitive)
   - `AWS_SECRET_ACCESS_KEY` = `<value>` (env var, sensitive)
   - `AWS_DEFAULT_REGION` = `us-east-1` (env var)
5. Apply the variable set to all 3 workspaces
6. Generate a **Team API Token** (`Settings → Teams → owners → Team API Token`)
7. Add the token as GitHub repo secret: `TF_API_TOKEN`

#### Step 3 — Configure AWS CLI Locally

```bash
aws configure
# AWS Access Key ID: <your key>
# AWS Secret Access Key: <your secret>
# Default region: us-east-1
# Default output format: json

# Verify
aws sts get-caller-identity
```

#### Step 4 — Write and Apply Base Terraform (Workspace 1)

Write `infra/terraform/base/` Terraform files (VPC + EKS as shown above), then:

```bash
# Option A: Let Terraform Cloud run on push (VCS-driven — recommended)
git add infra/terraform/base/
git commit -m "feat(infra): add VPC and EKS cluster config"
git push origin infra/phase-1-bootstrap
# → Terraform Cloud auto-queues a plan run for fraud-infra-base workspace
# → Review plan in app.terraform.io → Confirm Apply

# Option B: Trigger manually from local (for initial testing)
cd infra/terraform/base
terraform login          # authenticates to app.terraform.io
terraform init           # downloads providers, connects to TF Cloud backend
terraform plan
terraform apply
```

EKS provisioning takes ~12–15 minutes.

#### Step 5 — Configure kubectl

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name kong-fraud-platform

kubectl get nodes          # verify both node groups ready
kubectl get namespaces
```

#### Step 6 — Apply Addons (Workspace 2)

Push `infra/terraform/addons/` → Terraform Cloud runs and provisions:
- AWS Load Balancer Controller
- EBS CSI Driver
- Kubernetes namespaces (`kong`, `fintech-services`, `fraud-api`, `monitoring`, `security`)
- Network Policies
- External Secrets Operator

```bash
# Verify namespaces
kubectl get ns
# kong, fintech-services, fraud-api, monitoring, security

# Verify network policies
kubectl get networkpolicies -A
```

#### Step 7 — Deploy Kong Data Plane (Workspace 3)

Configure `infra/terraform/app/values/kong-dp-values.yaml`:
```yaml
image:
  repository: kong/kong-gateway
  tag: "3.7"

env:
  role: data_plane
  database: "off"
  cluster_control_plane: "<cp-endpoint>.cp0.konghq.com:443"
  cluster_server_name: "<cp-endpoint>.cp0.konghq.com"
  cluster_telemetry_endpoint: "<tp-endpoint>.tp0.konghq.com:443"
  cluster_telemetry_server_name: "<tp-endpoint>.tp0.konghq.com"
  lua_ssl_trusted_certificate: system
  konnect_mode: "on"
  vitals: "off"

secretVolumes:
  - kong-cluster-cert           # K8s secret containing cluster.crt + cluster.key

proxy:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"

replicaCount: 2
```

Create the Kong cluster cert secret in Kubernetes:
```bash
kubectl create secret generic kong-cluster-cert \
  --from-file=tls.crt=./konnect-cluster.crt \
  --from-file=tls.key=./konnect-cluster.key \
  -n kong
```

Push `infra/terraform/app/` → Terraform Cloud deploys Kong DP, Keycloak, and kube-prometheus-stack.

#### Step 8 — Verify Kong DP Connected to Konnect

```bash
kubectl get pods -n kong
# kong-dp-xxxx    1/1   Running

kubectl get svc -n kong
# NAME      TYPE           CLUSTER-IP    EXTERNAL-IP (NLB DNS)
# kong-dp   LoadBalancer   10.100.x.x    xxxx.elb.amazonaws.com

# Check Konnect UI: Control Plane → Data Plane Nodes → should show "Connected"
```

---

### AWS Secrets Management

Use **AWS Secrets Manager** + **External Secrets Operator** to inject secrets into Kubernetes pods:

```bash
# Store Kong Konnect cluster certs in Secrets Manager
aws secretsmanager create-secret \
  --name "kong-fraud/konnect-cluster-cert" \
  --secret-string file://konnect-cluster.crt

# External Secrets Operator syncs to K8s Secret automatically
# (configured in Terraform addons workspace)
```

Secrets to store in AWS Secrets Manager:
| Secret Name | Contents |
|-------------|----------|
| `kong-fraud/konnect-cluster-cert` | Konnect DP TLS cert + key |
| `kong-fraud/konnect-pat-token` | Kong Konnect PAT (for decK in CI) |
| `kong-fraud/keycloak-admin` | Keycloak admin credentials |
| `kong-fraud/llm-api-key` | Azure OpenAI API key (Phase 7) |
| `kong-fraud/fraud-api-mtls-cert` | Fraud API mTLS client cert (Phase 4) |

---

### Phase 1 Deliverables

| # | Deliverable | Location |
|---|-------------|----------|
| 1.1 | Terraform modules for VPC + EKS | `infra/terraform/base/` |
| 1.2 | Terraform modules for EKS add-ons + namespaces | `infra/terraform/addons/` |
| 1.3 | Helm values for Kong DP, Keycloak, Prometheus | `infra/terraform/app/values/` |
| 1.4 | Terraform Cloud workspaces configured and applied | app.terraform.io |
| 1.5 | EKS cluster running, all namespaces created | AWS EKS |
| 1.6 | Kong DP deployed and connected to Konnect | Konnect UI shows "Connected" |
| 1.7 | Secrets in AWS Secrets Manager, synced via ESO | Kubernetes secrets |
| 1.8 | `kubectl get nodes` returns healthy node groups | — |
| 1.9 | Prometheus + Grafana accessible (port-forward) | `monitoring` namespace |
| 1.10 | Keycloak accessible (port-forward for now) | `security` namespace |

---

### Phase 1 Estimated Cost — Demo Setup (AWS, us-east-1)

| Resource | Spec | Est. Monthly | Est. Per Day |
|----------|------|-------------|-------------|
| EKS Control Plane | Managed | $73 | ~$2.40 |
| EC2 — demo nodes | 3× t3.xlarge **Spot** (~$0.047/hr each) | ~$102 | ~$3.40 |
| NAT Gateway | 1× shared | ~$35 | ~$1.15 |
| NLB | **None** — use `kubectl port-forward` | $0 | $0 |
| Secrets Manager | ~5 secrets | <$3 | <$0.10 |
| **Total (approx.)** | | **~$213/month** | **~$7/day** |

> **Demo tip:** Spin up in the morning, `terraform destroy` the same evening.  
> A full-day demo run costs roughly **$7–10**. EKS control plane is the fixed cost at $2.40/day.

---

### Teardown Instructions (When Demo Is Done)

```bash
# 1. Destroy in reverse order — app first, then addons, then base
# Option A: via Terraform Cloud UI — queue destroy run on each workspace in order:
#   fraud-infra-app  →  fraud-infra-addons  →  fraud-infra-base

# Option B: from local CLI
cd infra/terraform/app     && terraform destroy -auto-approve
cd ../addons               && terraform destroy -auto-approve
cd ../base                 && terraform destroy -auto-approve

# 2. Verify nothing is left running (avoid surprise charges)
aws eks list-clusters
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId'
aws elbv2 describe-load-balancers
aws ec2 describe-nat-gateways --filter "Name=state,Values=available"

# 3. Remove local kubeconfig context
kubectl config delete-context arn:aws:eks:us-east-1:<account-id>:cluster/kong-fraud-platform
```

> After destroy, only the S3 state bucket and Secrets Manager secrets remain (cents/month).  
> Delete those manually if you want a complete clean-up:
> ```bash
> aws s3 rb s3://kong-fraud-tfstate --force
> aws secretsmanager delete-secret --secret-id kong-fraud/konnect-cluster-cert --force-delete-without-recovery
> ```

---

## Phase 2 — Upstream Service Deployment

**Goal:** Both upstream fintech services running and reachable from Kong.

### Services
| Service | Image | Port |
|---------|-------|------|
| Accounts Service | `kongcx/accounts-service:1.0.1` | 8081 |
| Transactions Service | `docker.io/kongcx/transactions-service:1.0.1` | 8082 |

### Tasks
| # | Task | Details |
|---|------|---------|
| 2.1 | Run upstream services via Docker Compose | Mount alongside Kong DP |
| 2.2 | Verify service health endpoints | `GET /health` for each service |
| 2.3 | Document available API endpoints | Capture OAS 3.0 specs from each service |
| 2.4 | Configure Mock fallback | Use Konnect Mock plugin or `konghq.httpbin.com` for when upstreams are down |
| 2.5 | Register services in Kong Konnect | Create Services + Routes for Accounts and Transactions APIs |

### Deliverables
- Both services running locally and in staging
- OAS specs captured: `services/accounts-api.yaml`, `services/transactions-api.yaml`
- Mock routes configured as fallback

---

## Phase 3 — Kong Gateway — Core Configuration

**Goal:** All consumer-facing routes proxied through Kong with base policies applied.

### Tasks
| # | Task | Details |
|---|------|---------|
| 3.1 | Define Kong declarative config | Use `deck` (decK) for all Kong objects as code |
| 3.2 | Create Services & Routes | Accounts, Transactions, (later) Fraud internal route |
| 3.3 | Apply Request Validator plugin | Schema validation against OAS specs |
| 3.4 | Apply Request Transformer plugin | Inject Correlation-ID header (`x-correlation-id`) |
| 3.5 | Apply Response Transformer plugin | Strip internal headers, redact sensitive fields |
| 3.6 | Apply PII Redaction | Use `pre-function` or `post-function` Lua plugin to mask card numbers, account IDs in logs |
| 3.7 | Enable Correlation ID plugin | Propagate trace ID end-to-end |

### Deliverables
- `kong/kong.yaml` — full declarative config
- All routes tested with `curl` / Insomnia

---

## Phase 4 — Security & Identity

**Goal:** Zero-Trust security across all API surfaces.

### 4.1 OAuth 2.0 / OIDC (Consumer-facing)

| # | Task | Details |
|---|------|---------|
| 4.1.1 | Deploy Keycloak (or use Kong Identity) | Configure realms: `fintech-mobile`, `fintech-partners`, `internal` |
| 4.1.2 | Create OAuth2 clients per consumer type | Mobile App, Fintech Partner, Internal Analytics |
| 4.1.3 | Apply OIDC plugin on Kong routes | Validate JWT, enforce scopes, extract consumer identity |
| 4.1.4 | Map JWT claims to Kong consumers | Use `jwt-claims-to-consumer` or `openid-connect` plugin consumer mapping |

### 4.2 mTLS (Internal Service-to-Service)

| # | Task | Details |
|---|------|---------|
| 4.2.1 | Generate CA and service certificates | Use `cfssl` or `step-ca` |
| 4.2.2 | Configure mTLS on Fraud API route | Kong `mtls-auth` plugin on internal route |
| 4.2.3 | Configure Transactions Service → Fraud API mTLS | Client certs mounted in service containers |

### 4.3 Consumer Scopes & Authorization

| Consumer | Allowed Scopes |
|----------|---------------|
| Mobile App | `accounts:read`, `payments:write`, `transactions:read` |
| Fintech Partner | `accounts:read`, `transactions:read` |
| Internal Analytics | `transactions:read`, `fraud:read` |

### Deliverables
- Keycloak realm config exported as JSON
- mTLS certificates in `infra/certs/`
- Kong OIDC plugin configs in declarative YAML

---

## Phase 5 — Traffic Governance

**Goal:** Rate limiting, caching, and canary deployment controls operational.

### Tasks
| # | Task | Details |
|---|------|---------|
| 5.1 | Rate Limiting Advanced plugin | Per-consumer limits: Mobile 1000/min, Partner 200/min, Internal 5000/min |
| 5.2 | Proxy Cache Advanced plugin | Cache `GET /accounts` and `GET /transactions` responses, TTL 30s, vary by consumer |
| 5.3 | Canary Release plugin | Route 10% of `/transactions` traffic to new service version for A/B testing |
| 5.4 | Request Size Limiting | Block payloads > 1 MB |
| 5.5 | IP Restriction plugin | Restrict Fraud API internal route to Kong DP subnet only |

### Deliverables
- Rate limit policies documented per consumer tier
- Canary routing verified via traffic split logs

---

## Phase 6 — Internal Fraud API Build

**Goal:** Standalone fraud decisioning service that Transactions Service calls internally.

### Architecture
```
Transactions Service ──(mTLS)──► Fraud API
                                    │
                          ┌─────────┴──────────┐
                          │  Rule Engine        │  (fast-fail, < 5ms)
                          │  Feature Extractor  │
                          │  LLM Reasoning      │  (async enrichment)
                          │  Decision Engine    │
                          └─────────────────────┘
                                    │
                          ALLOW / CHALLENGE / BLOCK
```

### Tasks
| # | Task | Details |
|---|------|---------|
| 6.1 | Bootstrap Fraud API service | Python (FastAPI) or Node.js — `fraud-api/` folder |
| 6.2 | Define API contract | OAS 3.0 spec: `POST /fraud/analyze` |
| 6.3 | Implement rule engine | Hard rules: velocity checks, geo anomaly, high-value threshold |
| 6.4 | Implement feature extractor | Extract: amount, merchant category, time-of-day, user history summary |
| 6.5 | Implement decision synthesizer | Combine rule score + LLM score → final decision |
| 6.6 | Add audit logging | Persist every decision with: request ID, features, rule scores, LLM reasoning, final outcome |
| 6.7 | Containerize Fraud API | `fraud-api/Dockerfile`, add to `docker-compose.yml` |
| 6.8 | Register internal route in Kong | Service + Route with mTLS auth — not consumer-facing |

### Fraud API Contract

**Request**
```json
POST /fraud/analyze
{
  "transaction_id": "txn_abc123",
  "account_id": "acc_xyz",
  "amount": 4500.00,
  "currency": "USD",
  "merchant_category": "WIRE_TRANSFER",
  "country": "NG",
  "timestamp": "2026-04-28T14:23:00Z",
  "consumer_type": "fintech_partner"
}
```

**Response**
```json
{
  "decision": "CHALLENGE",
  "risk_score": 0.82,
  "reasons": ["High-value wire transfer", "Unusual country for consumer profile"],
  "correlation_id": "corr_001",
  "model_version": "rules-v2+gpt4o"
}
```

### Deliverables
- `fraud-api/` service with Docker image
- `fraud-api/openapi.yaml` spec
- Unit tests for rule engine
- Integration test: Transactions Service → Fraud API

---

## Phase 7 — AI / LLM Abstraction Layer

**Goal:** LLM integrated and fully hidden behind Kong AI Gateway — consumers never touch the model directly.

### Design Principles
- LLM endpoint never exposed outside Fraud API
- All prompts controlled via Kong AI Prompt Guard / Prompt Template plugins
- Token usage logged and budget-capped per consumer

### Tasks
| # | Task | Details |
|---|------|---------|
| 7.1 | Configure AI Proxy plugin | Point to Azure OpenAI (or private LLM endpoint) |
| 7.2 | Define prompt templates | Structured fraud reasoning prompt: inject features, request explanation |
| 7.3 | Apply AI Prompt Guard plugin | Block prompt injection attempts, enforce response format |
| 7.4 | Apply AI Rate Limiting Advanced | Cap token budget per consumer / per hour |
| 7.5 | Enable AI Audit Log | Log all LLM requests/responses (sanitized) for compliance |
| 7.6 | Implement response filter in Fraud API | Strip raw LLM output; return only structured decision fields |
| 7.7 | Test LLM reasoning quality | Scenario tests: normal txn, high-risk, ATO attempt, partner misuse |

### LLM Prompt Template (Example)
```
You are a fraud analysis assistant for a fintech platform.
Analyze the following transaction features and provide a risk assessment.

Transaction Features:
- Amount: {{amount}} {{currency}}
- Merchant Category: {{merchant_category}}
- Country: {{country}}
- Consumer Type: {{consumer_type}}
- Rule Engine Score: {{rule_score}}

Respond ONLY in JSON:
{
  "risk_level": "LOW|MEDIUM|HIGH",
  "reasoning": "<one sentence explanation>",
  "recommended_action": "ALLOW|CHALLENGE|BLOCK"
}
```

### Deliverables
- Kong AI plugin config in `kong/kong.yaml`
- Prompt template in `fraud-api/prompts/fraud_analysis.txt`
- LLM integration test results documented

---

## Phase 8 — Observability

**Goal:** Full visibility into API traffic, fraud decisions, and LLM usage.

### Stack
| Tool | Role |
|------|------|
| Prometheus | Metrics scraping from Kong and Fraud API |
| Grafana | Dashboards: API traffic, fraud decision rates, LLM token usage |
| Kong Analytics (Konnect) | Built-in traffic analytics in Konnect UI |

### Tasks
| # | Task | Details |
|---|------|---------|
| 8.1 | Enable Prometheus plugin on Kong | Expose `/metrics` endpoint |
| 8.2 | Configure Prometheus scrape jobs | Add Kong DP and Fraud API targets |
| 8.3 | Build Grafana dashboards | (a) API Traffic, (b) Fraud Decisions, (c) LLM Usage, (d) Error Rates |
| 8.4 | Add custom metrics to Fraud API | Counters: `fraud_decisions_total{outcome}`, `rule_engine_latency_ms` |
| 8.5 | Configure alerting rules | Alert on: >5% BLOCK rate, LLM latency >2s, Kong 5xx >1% |
| 8.6 | Enable HTTP Log or Kafka Log plugin | Stream logs to SIEM / analytics pipeline |

### Key Metrics
```
kong_http_requests_total{service, route, status_code}
kong_latency_ms{type="request|upstream|kong"}
fraud_decisions_total{outcome="ALLOW|CHALLENGE|BLOCK"}
fraud_rule_score_histogram
llm_tokens_used_total{consumer, model}
llm_request_latency_ms
```

### Deliverables
- `infra/prometheus/prometheus.yml`
- `infra/grafana/dashboards/*.json`
- Alert rules in `infra/prometheus/alerts.yml`

---

## Phase 9 — CI/CD Automation & Developer Portal

### 9.1 CI/CD Pipeline

**Goal:** Data Plane configuration and Kong service/route setup built and deployed automatically.

| # | Task | Details |
|---|------|---------|
| 9.1.1 | Set up CI pipeline (GitHub Actions / GitLab CI) | Trigger on merge to `main` |
| 9.1.2 | OAS → Kong config conversion | Use `deck file openapi2kong` to convert OAS specs to declarative YAML |
| 9.1.3 | Validate Kong config | Run `deck validate` in CI |
| 9.1.4 | Diff and sync to Konnect | Run `deck sync --konnect-*` flags to apply config |
| 9.1.5 | Build and push Docker images | Fraud API image tagged with git SHA, pushed to registry |
| 9.1.6 | Deploy Data Plane | Apply Kong DP Helm chart or Docker Compose via CI |
| 9.1.7 | Run smoke tests post-deploy | `curl` health checks + Fraud API integration test |

**Pipeline Stages**
```
lint → validate-oas → openapi2kong → deck-validate → deck-diff → deck-sync → 
build-fraud-api → push-image → deploy-dp → smoke-test
```

### 9.2 Developer Portal

**Goal:** Private branded portal for partner onboarding and API discovery.

| # | Task | Details |
|---|------|---------|
| 9.2.1 | Enable Konnect Dev Portal | Configure private portal (not public) |
| 9.2.2 | Publish API specs | Accounts, Transactions APIs to portal |
| 9.2.3 | Configure RBAC for portal | Separate access for partners vs. internal teams |
| 9.2.4 | Enable API Key provisioning | Self-service partner credential issuance via portal |
| 9.2.5 | Build Service Catalog | Register all APIs with metadata: owner, SLA, version, deprecation policy |
| 9.2.6 | Configure Mock APIs | Enable Konnect Mock plugin so partners can test without hitting upstreams |
| 9.2.7 | Partner onboarding workflow | Document: registration → approval → credential issuance → sandbox test |

### Deliverables
- `ci/.github/workflows/deploy.yml` (or GitLab equivalent)
- `ci/openapi2kong.sh` conversion script
- Developer Portal configured in Konnect
- Service Catalog entries for all APIs

---

## Testing Strategy

### Test Levels
| Level | Scope | Tools |
|-------|-------|-------|
| Unit | Fraud API rule engine, feature extractor | pytest / Jest |
| Integration | Transactions → Fraud API, Kong → Upstream | Docker Compose + curl |
| Contract | OAS spec compliance | Schemathesis / Dredd |
| Security | OAuth flows, mTLS, PII redaction | OWASP ZAP, custom scripts |
| Load | Rate limiting enforcement, LLM latency under load | k6 |
| E2E | Full flow: Client → Kong → Transactions → Fraud → LLM | Insomnia / Bruno |

### Key Test Scenarios
1. **Normal transaction** → ALLOW decision, <200ms total latency
2. **High-value wire transfer to unusual country** → CHALLENGE + explanation
3. **Velocity attack** (50 txns/min from same account) → rate-limited at Kong + BLOCK at Fraud API
4. **Partner misuse** (scope violation) → 403 at Kong before reaching upstream
5. **LLM prompt injection attempt** → blocked by AI Prompt Guard
6. **Upstream service down** → Mock API returns stubbed response
7. **PII in response** → redacted before reaching consumer

---

## Phased Timeline (Indicative)

```
Week 1-2   │ Phase 1 + Phase 2  │ Infra + Upstreams running
Week 3     │ Phase 3            │ Kong core config, all routes proxied
Week 4     │ Phase 4            │ OAuth/OIDC + mTLS secured
Week 5     │ Phase 5            │ Rate limiting, caching, canary
Week 6-7   │ Phase 6            │ Fraud API built and integrated
Week 8     │ Phase 7            │ LLM integration + AI gateway
Week 9     │ Phase 8            │ Observability dashboards live
Week 10-11 │ Phase 9            │ CI/CD pipeline + Developer Portal
Week 12    │ Testing + Hardening│ Load tests, security review, documentation
```

---

## Repository Structure

```
kong-ps-ai-fraud-detection/
├── infra/
│   ├── docker-compose.yml          # Local stack: Kong DP, Keycloak, Prometheus, Grafana
│   ├── certs/                      # mTLS CA and service certificates
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   └── alerts.yml
│   └── grafana/
│       └── dashboards/
├── kong/
│   ├── kong.yaml                   # Full declarative Kong config (decK)
│   └── plugins/                    # Per-plugin config fragments
├── services/
│   ├── accounts-api.yaml           # OAS spec — Accounts Service
│   └── transactions-api.yaml       # OAS spec — Transactions Service
├── fraud-api/
│   ├── Dockerfile
│   ├── openapi.yaml                # Fraud API OAS spec
│   ├── src/
│   │   ├── rules/                  # Rule engine
│   │   ├── features/               # Feature extractor
│   │   ├── llm/                    # LLM client + prompt templates
│   │   └── decision/               # Decision synthesizer
│   ├── prompts/
│   │   └── fraud_analysis.txt      # LLM prompt template
│   └── tests/
├── ci/
│   ├── .github/workflows/
│   │   └── deploy.yml
│   └── openapi2kong.sh
├── portal/
│   └── service-catalog.yaml        # Service catalog metadata
├── architecture.md
├── ai-abstraction-layer.md
├── fraud-api-solution-requirements-design.md
├── transaction-with-fraud-detection-flow.md
├── requirments.txt
└── DEVELOPMENT_PLAN.md
```

---

## Key Dependencies & Technology Decisions

| Concern | Decision |
|---------|----------|
| API Gateway | Kong Konnect (managed Control Plane + self-hosted Data Plane) |
| Identity Provider | Keycloak (or Kong Identity) |
| Fraud API Runtime | Python / FastAPI |
| LLM Provider | Azure OpenAI (GPT-4o) — private endpoint |
| Config as Code | decK (`deck sync`) |
| Secrets | HashiCorp Vault or AWS Secrets Manager |
| CI/CD | GitHub Actions (or GitLab CI) |
| Observability | Prometheus + Grafana |
| OAS Conversion | `deck file openapi2kong` |
| Containerization | Docker + Docker Compose (local), Kubernetes-ready |

---

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| LLM latency spikes causing payment timeout | Medium | Async LLM call with rule-engine fast-fail; LLM enriches after ALLOW/BLOCK already issued for low-risk |
| PII leakage through logs | High | PII redaction plugin + audit log sanitization before export |
| Prompt injection via transaction data | Medium | AI Prompt Guard plugin on Kong; input sanitization in Fraud API |
| mTLS cert rotation complexity | Medium | Automate rotation with `step-ca` + cert-manager |
| Upstream service downtime during demo | Low | Mock API fallback always enabled on all routes |
| Rate limit bypass by partners | Low | Rate limiting enforced at Kong DP level, not trusting client headers |
