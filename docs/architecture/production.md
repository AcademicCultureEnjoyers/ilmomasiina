# Production architecture

**Status: designed and verified to build, NOT YET DEPLOYED.**

Production today is still the original Docker Compose deployment on Ubuntu. This document
describes both: what is running now, and what `infra/` will replace it with. Do not read the
"target" section as a description of the live system until the cutover in
[runbooks/cutover.md](../runbooks/cutover.md) is done and this notice is removed.

---

## What is running today

| | |
|---|---|
| Host | `46.62.170.58` (`ace-ilmo-4gb-hel1-1`), Hetzner hel1, Ubuntu |
| Orchestration | Docker Compose, `/opt/ilmomasiina/docker-compose.yml` |
| App | `ghcr.io/academiccultureenjoyers/ilmomasiina:production`, port 3000 internal |
| Database | `postgres:15` container, named volume `dbdata` |
| TLS | `caddy:2` container, `signup.academicculture.org` |
| Config | `/opt/ilmomasiina/.env`, hand-maintained |
| Deploys | **Manual.** `docker compose pull && docker compose up -d` over SSH |
| Backups | **None.** |
| Monitoring | **None.** |

Verified 2026-09-09 over SSH.

The image tag is `:production`, a moving tag. Because `docker-compose.yml` sets no
`pull_policy`, `docker compose up -d` alone does not fetch a newer image — which is how
production spent three months on an image built 2026-04-01 while a newer one sat in GHCR.

## Target architecture

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
