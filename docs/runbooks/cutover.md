# Cutover: Docker Compose on Ubuntu → NixOS

Moves `signup.academicculture.org` from the current Ubuntu host to a NixOS host that deploys
itself. **Not yet performed.**

There is no in-place conversion — this provisions a new server and moves DNS. The old host stays
up and untouched until the new one is verified, so the rollback at any point before step 7 is
"change nothing".

The database is ~9 MB, so the dump and restore take seconds. The user-visible outage is a DNS
change plus one Let's Encrypt issuance.

## Before you start

- [ ] `just check` passes locally (closure builds, infra tests pass)
- [ ] You can reach the current host: `ssh -i ~/.ssh/hetzner_ilmomasiina root@46.62.170.58`
- [ ] You have the `ace-shared-infra` 1Password vault (Hetzner token, DNS, `ace-infra-deploy` key)
- [ ] A GitHub **deploy key** exists for this repo with read access, and you have its private half
- [ ] Lower the DNS TTL for `signup.academicculture.org` to 60s **at least one old-TTL ahead**

That last point is the one that costs hours if skipped.

## 1. Capture the current state

```bash
ssh -i ~/.ssh/hetzner_ilmomasiina -o IdentitiesOnly=yes root@46.62.170.58

cd /opt/ilmomasiina
docker compose exec -T db pg_dump -U "$DB_USER" --no-owner --no-privileges "$DB_DATABASE" \
  | gzip -9 > /root/ilmomasiina-cutover.sql.gz
cp .env /root/ilmomasiina-env.backup
```

Copy both off the server before touching anything:

```bash
scp -i ~/.ssh/hetzner_ilmomasiina root@46.62.170.58:/root/ilmomasiina-cutover.sql.gz .
scp -i ~/.ssh/hetzner_ilmomasiina root@46.62.170.58:/root/ilmomasiina-env.backup .
```

Verify the dump is not empty and actually restores — a dump you have not read is not a backup:

```bash
gzip -t ilmomasiina-cutover.sql.gz
zcat ilmomasiina-cutover.sql.gz | grep -c "CREATE TABLE"
```

## 2. Provision the new host

```bash
just tofu-init
just provision
```

Note the new IP. Do **not** point DNS at it yet.

## 3. Prepare the secrets it will hold

The server fetches nothing at runtime; both files are placed at install.

```
extra-files/
├── etc/secrets/github-deploy-key      # read-only, this repo, mode 0600
└── etc/secrets/ilmomasiina.env        # from ilmomasiina-env.backup
```

Edit the env file before installing:

- Drop `DB_PASSWORD` — Postgres is loopback-only with `trust` for this role
- Keep `FEATHERS_AUTH_SECRET` and `NEW_EDIT_TOKEN_SECRET` **unchanged**: rotating them invalidates
  every outstanding signup edit link and every admin session
- Keep `DB_HOST` / `DB_PORT` / `DB_USER` / `DB_DATABASE` consistent with `modules/ilmomasiina.nix`
  (`127.0.0.1`, `5432`, `ilmomasiina`, `ilmomasiina`) — the module sets these itself, so entries
  in the env file are redundant but harmless if they agree, and a silent misconfiguration if they
  do not

The deploy key must be present at first boot, or the server cannot fetch its own config and
auto-deploy never starts.

## 4. Install

```bash
just install-production <NEW_IP>
```

This is destructive to the target host. It is a fresh server, so that is fine — but never run it
against the live one.

## 5. Restore the database

```bash
scp ilmomasiina-cutover.sql.gz root@<NEW_IP>:/tmp/
ssh root@<NEW_IP>

systemctl stop podman-ilmomasiina.service
zcat /tmp/ilmomasiina-cutover.sql.gz | sudo -u postgres psql ilmomasiina
systemctl start podman-ilmomasiina.service
```

## 6. Verify before DNS

Everything here works without DNS pointing at the new host.

```bash
ssh root@<NEW_IP>
systemctl is-active podman-ilmomasiina postgresql caddy
curl -sS -H 'Host: signup.academicculture.org' http://127.0.0.1:3000/api/events | head -c 400
sudo -u postgres psql ilmomasiina -c 'SELECT count(*) FROM signup;'
```

Compare that signup count against the old host. If they differ, stop — the restore was incomplete.

```bash
just backup-now && just backup-status
```

## 7. Move DNS

Point `signup.academicculture.org` at the new IP. Caddy issues a certificate on first request;
watch it:

```bash
ssh root@<NEW_IP> 'journalctl -u caddy -f'
```

Then, from anywhere:

```bash
curl -sSI https://signup.academicculture.org | head -5
```

**Rollback:** point DNS back. The old host is still running and still has its data — but any
signup made against the new host after this point exists only there, so past this step rollback
means reconciling two databases. This is the last cheap exit.

## 8. Confirm auto-deploy actually works

Do not skip this. An install that never deploys again looks identical to a healthy one for the
first fifteen minutes — that is exactly how ace-immich sat undeployed for three months.

```bash
just deploy-now
just deploy-logs
just deploy-status     # eligible and running should now agree
```

Then push a trivial change to `dev` and confirm it reaches production on its own.

## 9. Decommission the old host

Only after the new host has served traffic for at least a few days and taken at least one
successful nightly backup.

```bash
ssh -i ~/.ssh/hetzner_ilmomasiina root@46.62.170.58 'cd /opt/ilmomasiina && docker compose down'
```

Keep a final dump off-box, then delete the server in Hetzner. Remove the stale `46.62.170.58`
entries from `~/.ssh/known_hosts`.

Update [architecture/production.md](../architecture/production.md) — delete the "not yet deployed"
notice and the "running today" section — and close issues 1 and 2 in
[known-issues.md](../known-issues.md).
