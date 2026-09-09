# Known issues

Verified against the running system and the repo. Each entry records its evidence, so you can
re-check it rather than trust this file.

## Open

### 1. The old host is still running

**Severity: low, but it costs money and holds a copy of the signup data.**

`46.62.170.58` serves no traffic since the 2026-09-10 cutover, but is still powered on with its
database and `/opt/ilmomasiina/.env` intact. It is kept deliberately as the rollback path.

Decommission once the new host has served traffic for a few days and taken at least one
successful nightly backup — step 9 of [runbooks/cutover.md](runbooks/cutover.md).

### 2. Backups do not survive loss of the server

**Severity: medium.**

`modules/backup.nix` writes nightly dumps to `/var/backup/ilmomasiina` — the same disk as the
database. That protects against bad migrations, accidental deletion and corruption, but not
against loss of the host. This is the same gap ace-immich records as its largest open risk.

The database is ~9 MB (`pg_database_size`, 2026-09-09), so copying it off-box is nearly free.
`services.ilmomasiinaBackup.offsiteCommand` is the hook; it is currently unset.

### 3. No monitoring

**Severity: medium.**

Nothing watches deploys, the backup job, disk usage, or whether the site is up. The stale-image
problem resolved below went unnoticed for three months, and the identical failure in ace-immich
went unnoticed for the same duration. Any check reporting "last successful deploy" or "last
verified backup" would have surfaced both in the same week.

This is now the largest open risk to *operations*, because the pipeline that replaced the manual
one fails silently in exactly the same way if it breaks. `systemctl is-failed
nixos-upgrade.service` and `... ilmomasiina-backup.service` are meaningful health signals, and
`just deploy-status` / `just backup-status` already read them — but nothing runs them on a
schedule.

### 4. Production secrets have never been rotated

**Severity: low, rising with time.**

`/etc/secrets/ilmomasiina.env` holds `FEATHERS_AUTH_SECRET`, `NEW_EDIT_TOKEN_SECRET` and
`MAILGUN_API_KEY`. These values date from the original 2025-08-22 install and there is no record
of rotation; the cutover carried them over unchanged, deliberately, so that sessions and
outstanding signup edit links kept working.

Rotating them is a separate step with user-visible effects — every outstanding edit link and
admin session breaks — so it wants to happen between events, not during one.

They also exist in a second place now: the retired host's `/opt/ilmomasiina/.env`. Decommissioning
it (issue 1) removes that copy.

## Resolved on 2026-09-10

### Deploys were manual, and production ran three-month-old code

The running image was built 2026-04-01 (`363cfe45`) while a newer one from 2026-05-30 sat in
GHCR unpulled. The container had been recreated on 2026-05-30 at 19:19 UTC — 25 minutes *before*
that day's build finished at 19:44 — so `docker compose up -d` reused the local image.
`docker-compose.yml` set no `pull_policy` and nothing on the host polled the registry.

Fixed in two steps: production was pulled forward to current code on 2026-09-09, then migrated
on 2026-09-10 to a NixOS host that polls the `deploy` branch every 15 minutes and rebuilds
itself. Verified: `systemctl start nixos-upgrade.service` fetches, builds and exits 0.

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
