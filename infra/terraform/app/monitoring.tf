# ── kube-prometheus-stack ──────────────────────────────────────
# Includes: Prometheus, Grafana, Alertmanager, node-exporter,
#           kube-state-metrics — all in one chart.

resource "helm_release" "monitoring" {
  depends_on = [kubernetes_namespace.platform]

  name       = "kube-prometheus-stack"
  namespace  = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "59.1.0"

  values = [file("${path.module}/values/prometheus-values.yaml")]

  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  wait            = true
  timeout         = 600
  cleanup_on_fail = true
}
