output "usernames" {
  description = "Initial administrative username to use for VM-Series."
  value       = { for k, v in local.authentication : k => v.username }
}

output "passwords" {
  description = "Initial administrative password to use for VM-Series."
  value       = { for k, v in local.authentication : k => v.password }
  sensitive   = true
}

output "vmseries_mgmt_ips" {
  description = "Public management IP addresses for each VM-Series firewall."
  value       = { for k, v in module.vmseries : k => v.mgmt_ip_address }
}

output "metrics_instrumentation_keys" {
  description = "Application Insights instrumentation keys (one per firewall)."
  value       = try(module.ngfw_metrics[0].metrics_instrumentation_keys, null)
  sensitive   = true
}

output "bootstrap_storage_urls" {
  description = "Bootstrap file share URLs per storage account."
  value       = length(var.bootstrap_storages) > 0 ? { for k, v in module.bootstrap : k => v.file_share_urls } : null
  sensitive   = true
}

output "lb_frontend_ips" {
  description = "Frontend IP configurations for each load balancer."
  value       = length(var.load_balancers) > 0 ? { for k, v in module.load_balancer : k => v.frontend_ip_configs } : null
}

output "lb_backend_pool_ids" {
  description = "Backend pool resource IDs for each load balancer."
  value       = length(var.load_balancers) > 0 ? { for k, v in module.load_balancer : k => v.backend_pool_id } : null
}
