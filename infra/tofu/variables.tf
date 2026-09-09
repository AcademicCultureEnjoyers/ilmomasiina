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
  description = <<-EOT
    Hetzner server type for the production server.

    cx23 (2 vCPU / 4 GB / 40 GB, x86) is like-for-like with the box it
    replaces, which sits at ~0.00 load with 732 MB of 3.7 GB used. It is also
    what modules/disk.nix documents its partition layout for (BIOS boot,
    /dev/sda).

    Must be x86: the GHCR image is built linux/amd64 only. An ARM type (cax*)
    is cheaper for the same RAM but requires ace-deploy.yml to build
    multi-arch first, or the container will not start.

    Check availability per *datacenter*, not globally — /v1/server_types lists
    types that /v1/datacenters shows as unavailable in hel1. cx22 and cpx21
    both plan cleanly and then fail at apply for that reason.
  EOT
  type        = string
  default     = "cx23"
}

variable "hetzner_location" {
  description = "Hetzner datacenter location"
  type        = string
  default     = "hel1"
}

variable "dns_a_target" {
  description = <<-EOT
    IP that signup.academicculture.org resolves to.

    Set explicitly rather than derived from hcloud_server.production.ipv4_address,
    so that creating or replacing the server never moves live traffic as a side
    effect of `tofu apply`. Changing this value is the cutover.

    2026-09-10: cut over from the legacy Ubuntu host (46.62.170.58) to the
    NixOS host. To roll back, set this to 46.62.170.58 and apply — the old
    host is kept running until the new one has proven itself.
  EOT
  type        = string
  default     = "89.167.125.155"

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.dns_a_target))
    error_message = "dns_a_target must be a bare IPv4 address."
  }
}
