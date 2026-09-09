output "production_ip" {
  description = "Public IP address of the production server"
  value       = hcloud_server.production.ipv4_address
}
