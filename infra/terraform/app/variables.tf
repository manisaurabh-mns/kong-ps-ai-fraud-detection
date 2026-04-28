variable "konnect_cp_endpoint" {
  description = "Kong Konnect Control Plane endpoint (without https:// or port)"
  type        = string
  # Example: abc123def456.cp0.konghq.com
  # Set as sensitive workspace variable in Terraform Cloud
}

variable "konnect_tp_endpoint" {
  description = "Kong Konnect Telemetry endpoint (without https:// or port)"
  type        = string
  # Example: abc123def456.tp0.konghq.com
}

variable "konnect_cluster_cert" {
  description = "Contents of cluster.crt downloaded from Konnect UI"
  type        = string
  sensitive   = true
}

variable "konnect_cluster_key" {
  description = "Contents of cluster.key downloaded from Konnect UI"
  type        = string
  sensitive   = true
}

variable "keycloak_admin_password" {
  description = "Keycloak admin console password"
  type        = string
  sensitive   = true
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = "admin"
}
