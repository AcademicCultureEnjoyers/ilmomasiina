# Deploy and rollback

Applies **after** the cutover in [cutover.md](cutover.md). Until then production is the Docker
Compose stack and the manual fallback at the bottom of this page is the only path.

## Shipping a change

Merge to `dev`. That is the whole procedure.

```
push to dev
  → ace-deploy.yml: lint, typecheck, tests
  → build image, push to GHCR
  → resolve digest, commit it to infra/nixos/image.json
  → build the production NixOS closure (catches config errors here, not on the server)
  → fast-forward `deploy`
  → server's timer picks it up within ~15 min
```

A green CI run means the commit is **eligible** to deploy. It does not mean production changed.

```bash
just deploy-status   # eligible vs. running
just deploy-now      # don't wait for the timer
just deploy-logs     # follow the switch
```

`deploy-status` compares the `deploy` branch's pinned digest against what the host is actually
running. If they differ and the timer has fired, look at `deploy-logs`.

## Rolling back

```bash
just rollback
```

This pauses auto-deploy, then switches to the previous NixOS generation.

**The pause is not optional.** `deploy` still points at the bad commit, so an unpaused rollback
lasts exactly one timer interval before the server switches forward again. `just rollback` does
both; if you roll back by hand, pause first.

To make a rollback permanent, fix forward on `dev` and let CI promote the fix, then:

```bash
just deploy-resume
```

If you need `deploy` itself moved back, do it deliberately — CI only ever fast-forwards, so it
will refuse to promote over a branch that has been pointed backwards, and the next push will fail
loudly rather than silently overwriting your pin.

## When a deploy does not happen

The failure mode to expect is silence: the timer runs, reports success, and nothing changes. Check
in this order.

```bash
# 1. Did the unit run, and did it fail?
just ssh-prod
systemctl status nixos-upgrade.service
journalctl -u nixos-upgrade.service -n 100

# 2. Is the timer even enabled? (`just deploy-pause` disables it and survives reboot)
systemctl status nixos-upgrade.timer

# 3. Can the server fetch its own config?
GIT_SSH_COMMAND='ssh -i /etc/secrets/github-deploy-key -o IdentitiesOnly=yes' \
  git ls-remote git@github.com:AcademicCultureEnjoyers/ilmomasiina deploy

# 4. Can it pull the pinned image?
podman pull "$(jq -r '.repository + "@" + .digest' /etc/nixos-image.json 2>/dev/null)"
```

Step 3 is the one that has bitten this pattern before: a missing or revoked deploy key means the
server cannot fetch, and depending on the failure the unit may still exit 0.

`tests/nixos/test_auto_deploy_command.sh` covers a related trap — the flake ref contains `&`, and
unquoted interpolation made bash background the rebuild so the unit exited 0 in milliseconds
having deployed nothing. CI runs that test on every promote.

## Manual fallback

If auto-deploy is broken and a change must ship:

```bash
just deploy-pause
just ssh-prod
nixos-rebuild switch \
  --refresh \
  --flake "git+ssh://git@github.com/AcademicCultureEnjoyers/ilmomasiina?ref=deploy&dir=infra/nixos#production"
```

Quote the flake ref. Unquoted, the `&` backgrounds the command.

### Pre-cutover fallback (current production)

```bash
ssh -i ~/.ssh/hetzner_ilmomasiina -o IdentitiesOnly=yes root@46.62.170.58
cd /opt/ilmomasiina
docker compose pull && docker compose up -d
docker compose logs -f app
```

`pull` is required — the compose file sets no `pull_policy`, so `up -d` alone reuses the local
image.
