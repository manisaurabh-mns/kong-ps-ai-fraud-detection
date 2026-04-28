terraform {
  required_version = ">= 1.7.0"

  cloud {
    organization = "kong-ps-fraudplatform"
    workspaces {
      name = "fraud-infra-app"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.55"
    }
  }
}

# ── Read outputs from Workspace 1 (fraud-infra-base) ────────
data "tfe_outputs" "base" {
  organization = "kong-ps-fraudplatform"
  workspace    = "fraud-infra-base"
}

locals {
  cluster_name = data.tfe_outputs.base.values.cluster_name
  aws_region   = data.tfe_outputs.base.values.aws_region
}

# ── AWS provider ─────────────────────────────────────────────
provider "aws" {
  region = local.aws_region
}

# ── EKS auth data ────────────────────────────────────────────
data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = local.cluster_name
}

# ── Kubernetes provider ──────────────────────────────────────
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# ── Helm provider ─────────────────────────────────────────────
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
