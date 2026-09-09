# DNS records scoped to the project's subdomain.
# The zone (academicculture.org) is owned by the shared-infra repo.
# All record names are automatically prefixed with var.project_subdomain,
# so projects can only create records under their own subdomain.

data "hcloud_zone" "main" {
  name = "academicculture.org"
}

locals {
  dns_records_raw = jsondecode(file("${path.module}/dns-records.json"))

  # Deliberately NOT hcloud_server.production.ipv4_address. Resolving the token
  # straight to the new server would make `tofu apply` move live traffic the
  # moment the server exists — before NixOS is installed on it. The cutover
  # sets var.dns_a_target explicitly instead. See variables.tf.
  ip_map = {
    "@production" = var.dns_a_target
  }

  dns_records = [
    for r in local.dns_records_raw : {
      # "@" → project subdomain, anything else → prefixed with project subdomain
      name   = r.name == "@" ? var.project_subdomain : "${r.name}.${var.project_subdomain}"
      type   = r.type
      values = [for v in r.values : coalesce(lookup(local.ip_map, v, null), v)]
      ttl    = r.ttl
    }
  ]
}

# The signup A record predates this config — it was created by hand when the
# Docker Compose host was set up. Adopt it instead of creating it: a plain
# create fails with `uniqueness_error` (409), and forcing one would mean
# deleting the record that currently serves production.
#
# Config-driven import rather than `tofu import`, because the CLI's import
# command enforces a remote-version check that the Terraform Cloud workspace
# (~> 1.16.0) fails against the OpenTofu in our dev shell (1.12.6), while plan
# and apply do not.
#
# Safe to delete once this has been applied and the record is in state.
import {
  to = hcloud_zone_rrset.managed["signup::A"]
  # <zone id>/<record name>/<type>. Zone academicculture.org = 1337304.
  id = "1337304/signup/A"
}

resource "hcloud_zone_rrset" "managed" {
  for_each = { for r in local.dns_records : "${r.name}::${r.type}" => r }

  zone = data.hcloud_zone.main.name
  name = each.value.name
  type = each.value.type
  ttl  = each.value.ttl

  records = [for v in each.value.values : { value = v }]
}

check "no_unresolved_tokens" {
  assert {
    condition = !anytrue([
      for r in local.dns_records : anytrue([
        for v in r.values : startswith(v, "@")
      ])
    ])
    error_message = "dns-records.json contains an unresolved substitution token (a value starting with '@'). Check for typos in @production or other tokens."
  }
}
