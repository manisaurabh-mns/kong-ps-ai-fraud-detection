# ── Kong Konnect Cluster Certificate Secret ───────────────────
# Stores the Data Plane TLS certs (downloaded from Konnect UI)
# as a K8s secret in the kong namespace.
# These are injected into the Kong DP pod via secretVolumes.

resource "kubernetes_secret" "kong_cluster_cert" {
  depends_on = [kubernetes_namespace.platform]

  metadata {
    name      = "kong-cluster-cert"
    namespace = "kong"
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = var.konnect_cluster_cert
    "tls.key" = var.konnect_cluster_key
  }
}
