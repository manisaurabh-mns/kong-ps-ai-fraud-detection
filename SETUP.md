# Setup Guide — Kong AI Fraud Detection Platform

This guide covers three paths:
- **[Option A](#option-a--local-docker-compose)** — Run the full stack locally with Docker Compose (no AWS, no cost)
- **[Option A2](#option-a2--kong-dp-as-docker-container-on-a-linux-server)** — Kong DP as a standalone Docker container on a Linux server
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
3. **Data Plane Nodes** → **New Data Plane Node** → **Docker** tab
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

## Option A2 — Kong DP as Docker Container on a Linux Server

Use this when you have a Linux VM or server (on-prem, EC2, or any cloud VM) and want
to run **only the Kong Data Plane** as a standalone Docker container — without Docker Compose.
The upstream services (`accounts-service`, `transactions-service`) can run on the same host
or elsewhere; Kong will proxy to wherever they are.

### Pre-requisites

| Requirement | Detail |
|-------------|--------|
| Linux server | Ubuntu 22.04+ / RHEL 8+ / Amazon Linux 2023 |
| Docker Engine | 24.x — **not** Docker Desktop |
| Port access | `8000` (proxy), `8443` (proxy TLS), `8100` (status/metrics) open inbound |
| Kong Konnect access | Control Plane already created |

Install Docker Engine on Ubuntu:
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
docker --version
```

### Step 1 — Download Konnect Cluster Certificates

1. Log in to [cloud.konghq.com](https://cloud.konghq.com)
2. **Gateway Manager** → `fraud-platform-cp`
3. **Data Plane Nodes** → **New Data Plane Node** → **Docker** tab
4. Download `cluster.crt` and `cluster.key`

Copy the cert files to your Linux server:
```bash
# From your local machine
scp cluster.crt cluster.key user@<server-ip>:/etc/kong/certs/
```

Or create the directory and place them directly on the server:
```bash
sudo mkdir -p /etc/kong/certs
sudo cp cluster.crt cluster.key /etc/kong/certs/
sudo chmod 644 /etc/kong/certs/cluster.crt
sudo chmod 600 /etc/kong/certs/cluster.key
```

### Step 2 — Get Your Konnect Endpoints

**Gateway Manager** → `fraud-platform-cp` → **Overview** tab:
- **Cluster endpoint** → e.g. `abc123.cp0.konghq.com`
- **Telemetry endpoint** → e.g. `abc123.tp0.konghq.com`

### Step 3 — Run the Kong DP Container

```bash
docker run -d \
  --name kong-dp \
  --restart unless-stopped \
  -p 8000:8000 \
  -p 8443:8443 \
  -p 8100:8100 \
  -v /etc/kong/certs:/etc/kong/cluster:ro \
  -e KONG_ROLE=data_plane \
  -e KONG_DATABASE=off \
  -e KONG_CLUSTER_MTLS=pki \
  -e KONG_CLUSTER_CONTROL_PLANE=<your-cp-id>.cp0.konghq.com:443 \
  -e KONG_CLUSTER_SERVER_NAME=<your-cp-id>.cp0.konghq.com \
  -e KONG_CLUSTER_TELEMETRY_ENDPOINT=<your-cp-id>.tp0.konghq.com:443 \
  -e KONG_CLUSTER_TELEMETRY_SERVER_NAME=<your-cp-id>.tp0.konghq.com \
  -e KONG_CLUSTER_CERT=/etc/kong/cluster/cluster.crt \
  -e KONG_CLUSTER_CERT_KEY=/etc/kong/cluster/cluster.key \
  -e KONG_LUA_SSL_TRUSTED_CERTIFICATE=system \
  -e KONG_KONNECT_MODE=on \
  -e KONG_VITALS=off \
  -e KONG_LOG_LEVEL=notice \
  -e KONG_PROXY_ACCESS_LOG=/dev/stdout \
  -e KONG_PROXY_ERROR_LOG=/dev/stderr \
  -e KONG_STATUS_LISTEN=0.0.0.0:8100 \
  kong/kong-gateway:3.9
```

> Replace both `<your-cp-id>` occurrences with your actual Konnect CP ID.

### Step 4 — Verify the Container is Running

```bash
# Container running
docker ps | grep kong-dp

# Logs (watch for "connected to control plane" message)
docker logs kong-dp

# Status endpoint
curl http://localhost:8100/status
# Look for: "state": "running"
```

In Konnect UI: **Gateway Manager** → `fraud-platform-cp` → **Data Plane Nodes**
— the node should appear with status **Connected ●**

### Step 5 — Run Upstream Services (same host)

If running the upstream services on the same Linux server:

```bash
docker run -d --name accounts-service \
  --restart unless-stopped \
  kongcx/accounts-service:1.0.1

docker run -d --name transactions-service \
  --restart unless-stopped \
  docker.io/kongcx/transactions-service:1.0.1
```

> **Note:** For Kong to reach these containers by hostname, either:
> - Use Docker's default bridge network and reference by IP: `docker inspect accounts-service | grep IPAddress`
> - Or create a shared Docker network (recommended):

```bash
# Create a shared network
docker network create kong-net

# Re-run containers on the same network (add --network kong-net to each docker run)
# Kong can then resolve containers by name: http://accounts-service:8080
```

Update `kong/kong.yaml` service URLs to point to `http://accounts-service:8080` and
`http://transactions-service:8080` if using the shared network, then re-sync via decK.

### Step 6 — Sync Kong Config to Konnect

From any machine with decK installed and network access to Konnect:

```bash
deck gateway sync kong/kong.yaml \
  --konnect-token "$KONNECT_PAT" \
  --konnect-control-plane-name "fraud-platform-cp" \
  --select-tag fraud-platform
```

### Step 7 — Test

```bash
# From the Linux server or any machine that can reach it
curl -i http://<server-ip>:8000/v1/accounts
curl -i http://<server-ip>:8000/v1/transactions
```

### Managing the Container

```bash
# Stop
docker stop kong-dp

# Start
docker start kong-dp

# Restart (e.g. after cert rotation)
docker restart kong-dp

# View live logs
docker logs -f kong-dp

# Remove completely
docker stop kong-dp && docker rm kong-dp
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
| Kong DP container exits on Linux server | Cert path wrong or permissions | Verify `/etc/kong/certs/` contains both files; `cluster.key` must be `chmod 600` |
| Kong DP on Linux can't reach upstream | Containers on different Docker networks | Create a shared `docker network create kong-net` and attach all containers to it |
