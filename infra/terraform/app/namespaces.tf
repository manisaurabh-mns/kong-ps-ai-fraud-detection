# ── Namespaces ────────────────────────────────────────────────
# All platform namespaces created before any Helm release

locals {
  namespaces = ["kong", "fintech-services", "fraud-api", "monitoring", "security"]
}

resource "kubernetes_namespace" "platform" {
  for_each = toset(local.namespaces)

  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "project"                      = "kong-fraud-platform"
    }
  }
}
