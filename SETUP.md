# Setup Guide — Kong AI Fraud Detection Platform

This guide covers two paths:
- **[Option A](#option-a--local-docker-compose)** — Run the full stack locally with Docker Compose (no AWS, no cost)
- **[Option B](#option-b--aws-eks-via-cicd-pipeline)** — Deploy to AWS EKS via the GitHub Actions CI/CD pipeline

---

## Repository Structure (Quick Reference)

```
.github/workflows/deploy.yml   ← GitHub Actions pipeline
infra/
  docker-compose.yml           ← Local stack
  terraform/
    base/                      ← TF Workspace 1: VPC + EKS
    app/                       ← TF Workspace 2: Helm releases + namespaces
      values/
        kong-dp-values.yaml
        prometheus-values.yaml
        keycloak-values.yaml
kong/
  kong.yaml                    ← decK declarative config (synced to Konnect)
.env.example                   ← Template — copy to .env
```

---

## Option A — Local Docker Compose

Runs Kong DP (connected to your Konnect Control Plane), both upstream services,
Prometheus, and Grafana on your local machine. No AWS account needed.

### Pre-requisites

| Tool | Minimum Version | Install |
|------|----------------|---------|
| Docker Desktop | 4.x | https://docs.docker.com/get-docker/ |
| Docker Compose | v2.x (bundled with Desktop) | — |
| decK | 1.38+ | `brew install kong/deck/deck` |
| Kong Konnect account | — | https://konghq.com (you already have access) |

### Step 1 — Get Konnect Cluster Certificates

1. Log in to [cloud.konghq.com](https://cloud.konghq.com)
2. **Gateway Manager** → select your Control Plane (`fraud-platform-cp`)
3. **Data Plane Nodes** → **New Data Plane Node** → **Kubernetes** tab
4. Download `cluster.crt` and `cluster.key`
5. Place both files in `infra/certs/` (this folder is gitignored)

```bash
# Verify
ls infra/certs/
# cluster.crt  cluster.key
```

### Step 2 — Get Your Konnect Endpoints

On the same **Overview** tab of your Control Plane, copy:
- **Cluster endpoint** → looks like `abc123.cp0.konghq.com`
- **Telemetry endpoint** → looks like `abc123.tp0.konghq.com`

### Step 3 — Create Your `.env` File

```bash
cp .env.example .env
```

Edit `.env` with your values:

```bash
KONNECT_CP_ENDPOINT=<your-id>.cp0.konghq.com    # no https://, no port
KONNECT_TP_ENDPOINT=<your-id>.tp0.konghq.com
KONNECT_PAT=kpat_xxxxxxxxxxxxxxxxxxxxxxxxxxxx    # from Konnect → Account → PAT
KONNECT_CONTROL_PLANE_NAME=fraud-platform-cp
```

### Step 4 — Start the Local Stack

```bash
cd infra
docker compose up -d

# Check all containers are healthy
docker compose ps
```

Expected output:
```
NAME                    STATUS
accounts-service        Up (healthy)
transactions-service    Up (healthy)
kong-dp                 Up (healthy)
prometheus              Up
grafana                 Up
```

> **Troubleshooting:** If `kong-dp` is unhealthy, check logs:
> ```bash
> docker compose logs kong-dp
> ```
> Common cause: `cluster.crt` / `cluster.key` not in `infra/certs/` or wrong Konnect endpoints.

### Step 5 — Verify Kong is Connected to Konnect

```bash
# Check Konnect UI: Gateway Manager → your CP → Data Plane Nodes
# The DP node should appear as "Connected"

# Or check the status endpoint directly
curl http://localhost:8100/status
# Look for: "state": "running"
```

### Step 6 — Sync Kong Config to Konnect

```bash
# Validate the config locally first
deck file validate kong/kong.yaml

# Preview what will change (dry run)
deck gateway diff kong/kong.yaml \
  --konnect-token "$KONNECT_PAT" \
  --konnect-control-plane-name "$KONNECT_CONTROL_PLANE_NAME" \
  --select-tag fraud-platform

# Apply the config
deck gateway sync kong/kong.yaml \
  --konnect-token "$KONNECT_PAT" \
  --konnect-control-plane-name "$KONNECT_CONTROL_PLANE_NAME" \
  --select-tag fraud-platform
```

Expected sync output:
```
creating service accounts-service
creating service transactions-service
creating route accounts-list
creating route accounts-detail
creating route payments-initiate
creating route transactions-list-create
creating route transactions-detail
creating consumer mobile-app
creating consumer fintech-partner
creating consumer internal-analytics
Summary: created 9, updated 0, deleted 0
```

### Step 7 — Test the APIs

```bash
# Accounts API
curl -i http://localhost:8000/v1/accounts
# Expected: 200 or 401 (once auth is configured in Phase 4)

# Transactions API
curl -i http://localhost:8000/v1/transactions
```

### Step 8 — Open Grafana

Open [http://localhost:3000](http://localhost:3000)

- Username: `admin`
- Password: value of `GRAFANA_ADMIN_PASSWORD` in your `.env` (default: `admin`)
- The **Kong Official Dashboard** (ID 7424) is pre-provisioned.

### Stopping the Stack

```bash
cd infra
docker compose down          # stop and remove containers (data volumes preserved)
docker compose down -v       # also delete Prometheus/Grafana data volumes
```

---

## Option B — AWS EKS via CI/CD Pipeline

Deploys the full platform to AWS EKS using Terraform Cloud + GitHub Actions.
Everything is provisioned automatically on push to `main`.

### Pre-requisites

#### Tools (local machine — for verification and kubectl access only)

| Tool | Install |
|------|---------|
| AWS CLI v2 | `brew install awscli` or https://aws.amazon.com/cli/ |
| kubectl | `brew install kubectl` |
| Terraform CLI (optional — TF Cloud runs remotely) | `brew install terraform` |
| decK | `brew install kong/deck/deck` |

#### Accounts & Access

| Service | What you need |
|---------|--------------|
| AWS | Account with IAM user/role — `AdministratorAccess` (narrow after demo) |
| Terraform Cloud | Account at [app.terraform.io](https://app.terraform.io) |
| Kong Konnect | Control Plane access (you already have this) |
| GitHub | Admin access to this repository |

---

### One-Time Setup (do this before the first pipeline run)

#### 1. Create GitHub Environment

```
GitHub Repo → Settings → Environments → New environment
Name: demo
```

Optionally add yourself as a **Required reviewer** — this adds a manual approval
gate before the `destroy` action proceeds (recommended).

#### 2. Add GitHub Secrets

```
GitHub Repo → Settings → Secrets and variables → Actions → New repository secret
```

| Secret Name | Where to get it |
|-------------|----------------|
| `TF_API_TOKEN` | Terraform Cloud → org Settings → Teams → owners → **Team Token** |
| `AWS_ACCESS_KEY_ID` | AWS IAM → Users → your user → Security credentials |
| `AWS_SECRET_ACCESS_KEY` | Same as above |
| `AWS_DEFAULT_REGION` | Enter value: `us-east-1` |
| `KONNECT_PAT` | Konnect → Account (top right) → Personal Access Tokens → Generate |
| `KONNECT_CONTROL_PLANE_NAME` | Enter value: `fraud-platform-cp` |

#### 3. Create Terraform Cloud Organization

1. Log in to [app.terraform.io](https://app.terraform.io)
2. **New Organization** → Name: `kong-ps-fraudplatform`

#### 4. Create Two TF Cloud Workspaces

For each workspace below:
- **New Workspace** → **Version control workflow** → **GitHub** → select `kong-ps-ai-fraud-detection`
- Set the **working directory** as shown
- **Execution mode**: Remote (default)

| Workspace Name | Working Directory | Triggers on changes to |
|----------------|------------------|----------------------|
| `fraud-infra-base` | `infra/terraform/base` | `infra/terraform/base/**` |
| `fraud-infra-app` | `infra/terraform/app` | `infra/terraform/app/**` |

#### 5. Create AWS Credentials Variable Set

```
Terraform Cloud → org → Settings → Variable Sets → Create variable set
Name: aws-credentials
Scope: Apply to specific workspaces → fraud-infra-base + fraud-infra-app
```

Add these **environment variables** (mark all as sensitive):

| Key | Value |
|-----|-------|
| `AWS_ACCESS_KEY_ID` | your AWS key |
| `AWS_SECRET_ACCESS_KEY` | your AWS secret |
| `AWS_DEFAULT_REGION` | `us-east-1` |

#### 6. Add Workspace Variables to `fraud-infra-app`

```
Terraform Cloud → fraud-infra-app workspace → Variables → + Add variable
Category: Terraform variable   Sensitive: Yes
```

| Variable | Value |
|----------|-------|
| `konnect_cp_endpoint` | `<your-id>.cp0.konghq.com` (no https://) |
| `konnect_tp_endpoint` | `<your-id>.tp0.konghq.com` (no https://) |
| `konnect_cluster_cert` | Full contents of `cluster.crt` (paste the cert text) |
| `konnect_cluster_key` | Full contents of `cluster.key` (paste the key text) |
| `keycloak_admin_password` | a strong password |
| `grafana_admin_password` | a strong password |

> **How to get `cluster.crt` and `cluster.key`:**  
> Konnect → Gateway Manager → `fraud-platform-cp` → Data Plane Nodes  
> → New Data Plane Node → Kubernetes tab → download both files.

---

### Running the Pipeline

#### Deploy (apply)

```
GitHub → Actions → Deploy Kong Fraud Platform — EKS
→ Run workflow → Branch: main → Action: apply → Run workflow
```

**Pipeline stages** (~20–25 min total):

```
Job 1: TF Base    → Provision VPC + EKS cluster (~12–15 min)
Job 2: TF App     → Deploy namespaces, Kong DP, Keycloak, Prometheus (~5 min)
Job 3: decK Sync  → Validate and sync kong.yaml to Konnect (~1 min)
Job 4: Smoke Test → Verify Kong DP connected and responding (~2 min)
```

#### Auto-deploy on push

The pipeline also triggers automatically on any push to `main` that changes:
- `infra/terraform/**`
- `kong/kong.yaml`
- `.github/workflows/deploy.yml`

---

### After Deployment — Access Services

Configure `kubectl` to talk to the cluster:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name kong-fraud-platform

# Verify nodes are ready
kubectl get nodes
# NAME                         STATUS   ROLES    AGE
# ip-10-0-x-x.ec2.internal     Ready    <none>   5m
# ip-10-0-x-x.ec2.internal     Ready    <none>   5m

# Check all pods across platform namespaces
kubectl get pods -A | grep -v kube-system
```

#### Port-forward to Services

> The demo uses `kubectl port-forward` instead of a load balancer to save cost.
> Open each in a separate terminal.

```bash
# Kong Proxy — consumer API entry point
kubectl port-forward svc/kong-dp-kong-proxy 8000:80 -n kong

# Grafana — observability dashboards
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring

# Keycloak — identity provider admin console
kubectl port-forward svc/keycloak 8080:80 -n security
```

Or run the Terraform outputs command to get the exact service names:

```bash
cd infra/terraform/app
terraform output
```

#### Verify Kong DP is connected to Konnect

```bash
# Check the Data Plane node status in Konnect UI
# Gateway Manager → fraud-platform-cp → Data Plane Nodes
# Status should show: Connected ●

# Or use decK ping
deck gateway ping \
  --konnect-token "$KONNECT_PAT" \
  --konnect-control-plane-name "fraud-platform-cp"
# Expected: Successfully Konnected to the Kong organization!
```

#### Test the APIs

```bash
# Once port-forward is running on 8000
curl -i http://localhost:8000/v1/accounts
curl -i http://localhost:8000/v1/transactions

# Check Kong status
curl http://localhost:8100/status   # via exec, or inside the pod
```

#### Grafana Dashboards

Open [http://localhost:3000](http://localhost:3000)

- Username: `admin`
- Password: the `grafana_admin_password` you set in TF Cloud workspace variables
- **Kong Official Dashboard** (gnetId 7424) is pre-loaded under Dashboards

---

### Tearing Down (Destroy)

Run the destroy action — it tears down app tier first, then VPC+EKS:

```
GitHub → Actions → Deploy Kong Fraud Platform — EKS
→ Run workflow → Branch: main → Action: destroy → Run workflow
```

**Destroy order:**
```
Job 5: Destroy App   → Removes Helm releases, namespaces, K8s secrets
Job 6: Destroy Base  → Removes EKS cluster, VPC, NAT Gateway, IAM roles
```

Verify nothing is left running (avoids surprise charges):

```bash
aws eks list-clusters --region us-east-1
# Should return: { "clusters": [] }

aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --region us-east-1 \
  --query 'Reservations[].Instances[].InstanceId'
# Should return: []

aws ec2 describe-nat-gateways \
  --filter "Name=state,Values=available" \
  --region us-east-1 \
  --query 'NatGateways[].NatGatewayId'
# Should return: []
```

> After a successful destroy, only the **Terraform state S3 bucket** (created by TF Cloud)
> and any **Terraform Cloud workspace state files** remain — these cost cents/month.

---

## Updating Kong Config

To change routes, plugins, or consumers — edit `kong/kong.yaml` and either:

**Locally:**
```bash
deck gateway sync kong/kong.yaml \
  --konnect-token "$KONNECT_PAT" \
  --konnect-control-plane-name "$KONNECT_CONTROL_PLANE_NAME" \
  --select-tag fraud-platform
```

**Via pipeline:**
```bash
git add kong/kong.yaml
git commit -m "feat(kong): add rate limiting to accounts route"
git push origin main
# Pipeline triggers automatically on push to main
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `kong-dp` container exits immediately (local) | Wrong Konnect endpoint or missing certs | Check `docker compose logs kong-dp`; verify `infra/certs/` has both files and `.env` endpoints are correct |
| `deck gateway ping` fails | Wrong `KONNECT_PAT` or CP name | Regenerate PAT in Konnect UI; verify `KONNECT_CONTROL_PLANE_NAME` matches exactly |
| TF Cloud plan fails with `no workspace` | Workspace not yet created or VCS not connected | Create workspace in TF Cloud and link to repo |
| TF App fails: `cluster not found` | `fraud-infra-base` not applied yet | Run base workspace apply first before app |
| `kubectl` can't connect | kubeconfig not updated | Run `aws eks update-kubeconfig --region us-east-1 --name kong-fraud-platform` |
| Kong pods `CrashLoopBackOff` on EKS | `kong-cluster-cert` secret missing or wrong | Check `kubectl get secret kong-cluster-cert -n kong`; verify cert contents in TF Cloud workspace variable |
| Grafana shows no Kong metrics | Prometheus scrape target wrong | Check `kubectl get svc -n kong` for correct service name; update `prometheus-values.yaml` if needed |
