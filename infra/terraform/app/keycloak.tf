# ── Keycloak (Identity Provider) ──────────────────────────────
# Deployed in standalone mode for demo (no external DB).
# Phase 4 will configure realms and clients.

resource "helm_release" "keycloak" {
  depends_on = [kubernetes_namespace.platform]

  name       = "keycloak"
  namespace  = "security"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "keycloak"
  version    = "21.4.1"

  values = [file("${path.module}/values/keycloak-values.yaml")]

  set_sensitive {
    name  = "auth.adminPassword"
    value = var.keycloak_admin_password
  }

  wait            = true
  timeout         = 600
  cleanup_on_fail = true
}
