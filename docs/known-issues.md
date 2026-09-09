# Known issues

Verified against the running system and the repo. Each entry records its evidence, so you can
re-check it rather than trust this file.

## Open

### 1. The NixOS deployment is not live yet

**Severity: high — everything else in `infra/` is theory until this lands.**

`infra/nixos` builds and its production closure evaluates, but production is still the original
Docker Compose stack on Ubuntu. Until the cutover, deploys remain manual and the auto-deploy
pipeline described in [architecture/production.md](architecture/production.md) is not running.

Evidence (2026-09-09): `docker ps` on `46.62.170.58` shows `ilmomasiina-app-1`,
`ilmomasiina-db-1` and `ilmomasiina-caddy-1`; there is no NixOS host and no `deploy` branch
consumer.

Next step: [runbooks/cutover.md](runbooks/cutover.md).

### 2. Production is running three-month-old code

**Severity: medium.**

The running container's image was built 2026-04-01 (revision `363cfe45`). A newer image built
2026-05-30 from `23f35e16` — the CSV delimiter fix — has been sitting in GHCR unpulled ever since,
and `dev` has since advanced well past both.

Evidence: `docker inspect ilmomasiina-app-1` reports image `sha256:0a6cfe6c…` created
2026-04-01T08:39:08Z with label `org.opencontainers.image.revision=363cfe45…`. The container was
recreated 2026-05-30T19:19:51Z — 25 minutes *before* that day's build finished at 19:44 UTC — so
the new image was never pulled.

Cause: `/opt/ilmomasiina/docker-compose.yml` sets no `pull_policy`, so `docker compose up -d`
reuses the local image. Nothing on the host polls the registry.

This resolves itself at cutover. It can also be fixed immediately with `docker compose pull &&
docker compose up -d`.

### 3. Backups do not survive loss of the server

**Severity: medium.**

`modules/backup.nix` writes nightly dumps to `/var/backup/ilmomasiina` — the same disk as the
database. That protects against bad migrations, accidental deletion and corruption, but not
against loss of the host. This is the same gap ace-immich records as its largest open risk.

The database is ~9 MB (`pg_database_size`, 2026-09-09), so copying it off-box is nearly free.
`services.ilmomasiinaBackup.offsiteCommand` is the hook; it is currently unset.

### 4. No monitoring

**Severity: medium.**

Nothing watches deploys, the backup job, disk usage, or whether the site is up. Issue 2 above went
unnoticed for three months, and the identical failure in ace-immich went unnoticed for the same
duration. Any check reporting "last successful deploy" or "last verified backup" would have
surfaced both in the same week.

After cutover, `systemctl is-failed nixos-upgrade.service` and `... ilmomasiina-backup.service`
on the host become meaningful health signals — `just deploy-status` and `just backup-status`
already read them, but nothing runs them on a schedule.

### 5. Production secrets have never been rotated

**Severity: low, rising with time.**

`/opt/ilmomasiina/.env` holds `FEATHERS_AUTH_SECRET`, `NEW_EDIT_TOKEN_SECRET`, `DB_PASSWORD` and
`MAILGUN_API_KEY`. The file dates from the original 2025-08-22 install and there is no record of
rotation. The cutover copies these values to the new host as-is, which keeps sessions and edit
links valid — rotating them is a deliberate, separate step with user-visible effects (existing
signup edit links break).

## Resolved on 2026-09-09

### The dev shell was broken

`nix develop` failed outright: the flake pinned `nodejs_20`, removed from nixpkgs at its
2026-04-30 EOL. `flake.lock` was gitignored, so the shell re-resolved nixpkgs to unstable HEAD on
every entry and eventually picked up the removal. The pin also disagreed with `.nvmrc` (24), so
the dev shell and CI were on different Node majors.

Fixed by moving to `nodejs_24`, replacing the deprecated `nodePackages.pnpm` alias, and committing
`flake.lock`.

### A Postgres data directory was committed to the repo

`.pgdata` — 968 files, 39 MB, created by the dev shell's `shellHook` — was committed in
`7555e78f`. `.gitignore` listed it, which has no effect on already-tracked paths. Removed from
the index.

### Fork edits to upstream CI made every upstream merge a conflict

`docker-build.yml` and `lint-test.yml` carried 49 lines of ACE-specific changes. Both are upstream
files. Restored to byte-identical with `Tietokilta/ilmomasiina`; the fork's build now lives in
`ace-deploy.yml`, which upstream will never touch.
