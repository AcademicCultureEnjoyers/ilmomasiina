# The deploy SSH key is managed by ace-shared-infra; reference it as a data source.
data "hcloud_ssh_key" "deploy" {
  name = "deploy"
}

resource "hcloud_server" "production" {
  name        = "ilmomasiina-production"
  server_type = var.production_server_type
  location    = var.hetzner_location
  image       = "debian-12"
  ssh_keys    = [data.hcloud_ssh_key.deploy.id]

  labels = {
    role    = "production"
    project = "ilmomasiina"
  }
}

# No separate volume. Unlike ace-immich there is no media to store: the app is
# stateless and the database is ~9 MB, so both live on the server's local disk.
# This means a Hetzner volume snapshot is not a backup path here — see
# modules/backup.nix and docs/known-issues.md.
