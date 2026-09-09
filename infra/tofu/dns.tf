# DNS records scoped to the project's subdomain.
# The zone (academicculture.org) is owned by the shared-infra repo.
# All record names are automatically prefixed with var.project_subdomain,
# so projects can only create records under their own subdomain.

data "hcloud_zone" "main" {
  name = "academicculture.org"
}

locals {
  dns_records_raw = jsondecode(file("${path.module}/dns-records.json"))

  ip_map = {
    "@production" = try(hcloud_server.production.ipv4_address, null)
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
