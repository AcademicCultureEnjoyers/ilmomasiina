variable "hcloud_token" {
  sensitive   = true
  description = "Hetzner Cloud API token (from shared-infra vault)"
  type        = string
}

variable "project_subdomain" {
  description = "Project's subdomain under academicculture.org (e.g., 'signup'). All DNS records are scoped to this subdomain."
  type        = string
}

variable "production_server_type" {
  description = "Hetzner server type for the production server. cx22 (2 vCPU / 4 GB / 40 GB) matches the box this replaces, which sits at ~0.00 load and 8.6 GB used."
  type        = string
  default     = "cx22"
}

variable "hetzner_location" {
  description = "Hetzner datacenter location"
  type        = string
  default     = "hel1"
}
