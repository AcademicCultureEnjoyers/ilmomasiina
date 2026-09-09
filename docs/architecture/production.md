# Production architecture

**Live since 2026-09-10.** Verified against the running server.

`signup.academicculture.org` resolves to `89.167.125.155`, a NixOS host that deploys itself.
The previous Docker Compose host on Ubuntu was destroyed on 2026-09-10; this is now the only
server serving Ilmomasiina.

| | |
|---|---|
| Host | `89.167.125.155` (`ilmomasiina-production`), Hetzner hel1, cx23, NixOS |
| App | podman, `ghcr.io/academiccultureenjoyers/ilmomasiina@sha256:…` pinned by digest |
| Database | PostgreSQL 16, native (`services.postgresql`), loopback only |
| TLS | Caddy, Let's Encrypt, `signup.academicculture.org` |
| Config | `/etc/secrets/ilmomasiina.env`, placed at install |
| Deploys | Automatic. Server polls `deploy` every 15 min and rebuilds itself |
| Backups | Nightly `pg_dump`, 30-day retention — local only |
| Monitoring | **None.** |

## Architecture

A single Hetzner VPS running NixOS, deploying itself.

```
GitHub (AcademicCultureEnjoyers/ilmomasiina)
  │
  ├── push to dev
  │     └── ace-deploy.yml: lint → test → build image → push to GHCR
  │                          → pin digest in infra/nixos/image.json
  │                          → fast-forward `deploy` branch
  │
  └── `deploy` branch ◄──── polled every 15 min ────┐
                                                     │
  Hetzner VPS (NixOS)                                │
  ├── nixos-upgrade.timer ───────────────────────────┘
  │     └── nixos-rebuild switch --flake ...?ref=deploy&dir=infra/nixos#production
  ├── podman: ilmomasiina @ sha256:...   (host network, :3000)
  ├── postgresql 16                      (native, loopback only)
  ├── caddy                              (443 → 127.0.0.1:3000)
  └── ilmomasiina-backup.timer           (nightly pg_dump)
```

| Concern | How it is handled |
|---|---|
| App | OCI container from GHCR, **pinned by digest** in `infra/nixos/image.json` |
| Database | `services.postgresql` (16), native, listening on loopback only |
| TLS | Caddy, automatic Let's Encrypt for `signup.academicculture.org` |
| Server + DNS | OpenTofu against Hetzner Cloud |
| Admin access | Tailscale — administrative only, nothing in the deploy path depends on it |
| Secrets | `/etc/secrets/ilmomasiina.env`, placed at install; the server fetches nothing at runtime |
| Deploys | The server pulls the `deploy` branch and rebuilds itself every 15 min |
| Backups | Nightly `pg_dump`, 30-day retention — **local only**, see [known-issues](../known-issues.md) |

### Why pull-based

Nothing needs inbound access to the host. CI holds no SSH key, no server token, and no route to
production. A compromised CI account can publish a bad image, but cannot reach the server.

A green CI run means a commit is *eligible* to deploy, not that production changed. `just
deploy-status` is the only thing that answers the latter.

### Why the app is a container and not a Nix derivation

`ace-project-template` packages the application as a Nix derivation. That works when the closure
can be substituted from a binary cache — but the Attic cache that pattern assumes was
decommissioned in September 2026, which silently broke ace-immich's deploys for three months.

Ilmomasiina has a pnpm monorepo to build. Building it on a 4 GB server on every deploy would be
slow and fragile. Consuming the image that CI already publishes keeps the NixOS closure entirely
substitutable from `cache.nixos.org`, so the server builds essentially nothing — the property
that makes the immich pipeline reliable, reached by a different route.

### Why the digest, not the tag

`:production` moves on every push to dev. If the server tracked it:

- `nixos-rebuild switch` would be a no-op while the running code changed underneath it, so the
  NixOS generation would no longer describe what is running;
- rollback would have nothing to roll back to;
- `deploy` would no longer identify a specific, tested artifact.

CI resolves the tag to a digest and commits it. `git log infra/nixos/image.json` is the deploy
history.

### Why Postgres is not containerised

The app is stateless; the database is the only thing worth protecting. Running it under
`services.postgresql` gives it NixOS' backup, upgrade and systemd integration, and a stable data
path rather than a container volume.
