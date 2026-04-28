output "kong_proxy_service" {
  description = "kubectl port-forward command to reach Kong proxy locally"
  value       = "kubectl port-forward svc/kong-dp-kong-proxy 8000:80 -n kong"
}

output "grafana_port_forward" {
  description = "kubectl port-forward command to reach Grafana locally"
  value       = "kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring"
}

output "keycloak_port_forward" {
  description = "kubectl port-forward command to reach Keycloak locally"
  value       = "kubectl port-forward svc/keycloak 8080:80 -n security"
}
