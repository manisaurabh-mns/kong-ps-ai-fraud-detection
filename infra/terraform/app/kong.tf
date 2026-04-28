# ── Kong Data Plane ────────────────────────────────────────────
# Deployed in Data Plane mode — connects to Konnect Control Plane.
# Receives config from Konnect; no local database.

resource "helm_release" "kong_dp" {
  depends_on = [
    kubernetes_namespace.platform,
    kubernetes_secret.kong_cluster_cert
  ]

  name       = "kong-dp"
  namespace  = "kong"
  repository = "https://charts.konghq.com"
  chart      = "kong"
  version    = "2.43.0"   # pin chart version for reproducibility

  values = [file("${path.module}/values/kong-dp-values.yaml")]

  # Inject Konnect endpoints at deploy time
  set {
    name  = "env.cluster_control_plane"
    value = "${var.konnect_cp_endpoint}:443"
  }
  set {
    name  = "env.cluster_server_name"
    value = var.konnect_cp_endpoint
  }
  set {
    name  = "env.cluster_telemetry_endpoint"
    value = "${var.konnect_tp_endpoint}:443"
  }
  set {
    name  = "env.cluster_telemetry_server_name"
    value = var.konnect_tp_endpoint
  }

  wait             = true
  timeout          = 300
  cleanup_on_fail  = true
}
