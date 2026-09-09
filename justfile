# Operational tasks for the ACE Ilmomasiina deployment.
#
#   just --list          all recipes
#   just deploy-status   what production is running vs. what is eligible
#
# Deploys are pull-based: CI advances the `deploy` branch, and the server
# rebuilds itself on a 15-minute timer. Nothing here pushes to production, and
# a green CI run does not mean production changed — `deploy-status` is the only
# thing that answers that.

set shell := ["bash", "-euo", "pipefail", "-c"]

# The key is served by the 1Password agent for the new NixOS host; the legacy
# Ubuntu host still uses a local key. Override with PROD_HOST=... just <recipe>
# during the cutover, while DNS and the box do not yet agree.
prod_host := env_var_or_default("PROD_HOST", "signup.academicculture.org")
ssh_opts  := "-o ConnectTimeout=10"

_default:
    @just --list

# ---------------------------------------------------------------- #
# Access
# ---------------------------------------------------------------- #

# SSH into production.
ssh-prod:
    ssh {{ssh_opts}} root@{{prod_host}}

# ---------------------------------------------------------------- #
# Deploys
# ---------------------------------------------------------------- #

# What production is running, versus what is eligible to deploy.
deploy-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "── Eligible (deploy branch) ──────────────────────────────"
    git fetch origin deploy --quiet 2>/dev/null || echo "  (no deploy branch yet)"
    if git rev-parse --verify --quiet origin/deploy >/dev/null; then
        git --no-pager log -1 --format="  commit  %h %s%n  when    %ad" --date=iso origin/deploy
        echo "  image   $(git show origin/deploy:infra/nixos/image.json 2>/dev/null | jq -r '.digest // "?"')"
    fi
    echo
    echo "── Running (production) ──────────────────────────────────"
    ssh {{ssh_opts}} root@{{prod_host}} '
        echo "  generation  $(readlink -f /run/current-system | sed "s|/nix/store/||")"
        echo "  app image   $(podman inspect ilmomasiina --format "{{{{.ImageName}}}}" 2>/dev/null || echo "not running")"
        echo "  app state   $(systemctl is-active podman-ilmomasiina.service 2>/dev/null || true)"
        echo "  last deploy $(systemctl show nixos-upgrade.service -p ExecMainExitTimestamp --value 2>/dev/null || true)"
        echo "  deploy unit $(systemctl is-failed nixos-upgrade.service 2>/dev/null || true)"
    '

# Trigger a deploy now instead of waiting for the timer.
deploy-now:
    ssh {{ssh_opts}} root@{{prod_host}} 'systemctl start nixos-upgrade.service' &
    just deploy-logs

# Follow the current or most recent deploy.
deploy-logs:
    ssh {{ssh_opts}} root@{{prod_host}} 'journalctl -u nixos-upgrade.service -f -n 50'

# Stop auto-deploy while investigating. Survives reboot.
deploy-pause:
    ssh {{ssh_opts}} root@{{prod_host}} 'systemctl stop nixos-upgrade.timer && systemctl disable nixos-upgrade.timer'
    @echo "Auto-deploy paused. Resume with: just deploy-resume"

# Resume auto-deploy.
deploy-resume:
    ssh {{ssh_opts}} root@{{prod_host}} 'systemctl enable --now nixos-upgrade.timer'
    @echo "Auto-deploy resumed."

# Roll back to the previous NixOS generation (pauses auto-deploy first).
rollback:
    # Rolling back without pausing would last exactly one timer interval: the
    # deploy branch still points at the bad commit, so the server would switch
    # straight back to it. Pause is part of the rollback, not a separate step.
    @echo "Pausing auto-deploy so the timer does not undo this..."
    just deploy-pause
    ssh {{ssh_opts}} root@{{prod_host}} 'nixos-rebuild switch --rollback'
    @echo "Rolled back. Fix the deploy branch, then: just deploy-resume"

# ---------------------------------------------------------------- #
# Application
# ---------------------------------------------------------------- #

# Follow application logs.
logs:
    ssh {{ssh_opts}} root@{{prod_host}} 'journalctl -u podman-ilmomasiina.service -f -n 100'

# Restart the application container.
restart:
    ssh {{ssh_opts}} root@{{prod_host}} 'systemctl restart podman-ilmomasiina.service'

# ---------------------------------------------------------------- #
# Backups
# ---------------------------------------------------------------- #

# List backups and flag whether any copy exists off-box.
backup-status:
    #!/usr/bin/env bash
    set -uo pipefail
    ssh {{ssh_opts}} root@{{prod_host}} '
        echo "── Dumps on the server ──"
        ls -lh /var/backup/ilmomasiina/ 2>/dev/null | tail -n +2 || echo "  none"
        echo
        echo "  last run:  $(systemctl show ilmomasiina-backup.service -p ExecMainExitTimestamp --value 2>/dev/null || true)"
        echo "  status:    $(systemctl is-failed ilmomasiina-backup.service 2>/dev/null || true)"
    '
    echo
    echo "  NOTE: dumps are on the same disk as the database. They do not"
    echo "        survive loss of the server. See docs/known-issues.md."

# Take an ad-hoc backup now.
backup-now:
    ssh {{ssh_opts}} root@{{prod_host}} 'systemctl start ilmomasiina-backup.service && journalctl -u ilmomasiina-backup.service -n 20 --no-pager'

# Copy the newest dump to ./backups/ locally.
backup-fetch:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p backups
    latest=$(ssh {{ssh_opts}} root@{{prod_host}} 'ls -t /var/backup/ilmomasiina/*.sql.gz 2>/dev/null | head -1')
    test -n "$latest" || { echo "no backups on the server"; exit 1; }
    scp {{ssh_opts}} "root@{{prod_host}}:$latest" backups/
    echo "fetched $(basename "$latest") -> backups/"

# ---------------------------------------------------------------- #
# Provisioning — see docs/runbooks/cutover.md
# ---------------------------------------------------------------- #

export OP_ACCOUNT := env_var_or_default("OP_ACCOUNT", "my.1password.com")

# Initialise OpenTofu (Terraform Cloud backend).
tofu-init:
    cd infra/tofu && op run --env-file=.env.op -- tofu init

# Preview infrastructure changes.
tofu-plan:
    cd infra/tofu && op run --env-file=.env.op -- tofu plan

# Create the Hetzner server and DNS records.
provision:
    cd infra/tofu && op run --env-file=.env.op -- tofu apply
    @echo
    @echo "Server created. DNS is NOT yet pointed at it — that is step 7 of the cutover."
    @echo "Next: just install-production \$(cd infra/tofu && tofu output -raw production_ip)"

# Show the provisioned server's IP.
prod-ip:
    cd infra/tofu && tofu output -raw production_ip

# DESTRUCTIVE. Install NixOS onto a freshly provisioned server.
install-production ip:
    #!/usr/bin/env bash
    # Wipes the target disk. Only ever run against a new server — never
    # against the host currently serving signup.academicculture.org.
    #
    # Expects extra-files/ to contain, per docs/runbooks/cutover.md:
    #   etc/secrets/github-deploy-key    (read-only deploy key for this repo)
    #   etc/secrets/ilmomasiina.env      (app config and secrets)
    set -euo pipefail
    if [ ! -f extra-files/etc/secrets/github-deploy-key ]; then
        echo "extra-files/etc/secrets/github-deploy-key is missing." >&2
        echo "Without it the server cannot fetch its own config and auto-deploy never starts." >&2
        exit 1
    fi
    if [ ! -f extra-files/etc/secrets/ilmomasiina.env ]; then
        echo "extra-files/etc/secrets/ilmomasiina.env is missing — the app will not start." >&2
        exit 1
    fi
    chmod 600 extra-files/etc/secrets/*
    read -rp "This ERASES {{ip}}. Type the IP again to confirm: " confirm
    [ "$confirm" = "{{ip}}" ] || { echo "aborted"; exit 1; }
    nix run github:nix-community/nixos-anywhere -- \
        --extra-files extra-files \
        --flake ./infra/nixos#production \
        --target-host "root@{{ip}}"

# ---------------------------------------------------------------- #
# Local checks — these are what CI runs
# ---------------------------------------------------------------- #

# Build the production NixOS closure locally.
build:
    nix build ./infra/nixos#nixosConfigurations.production.config.system.build.toplevel \
      --no-link --extra-experimental-features "nix-command flakes"

# Run the infrastructure test suite.
test-infra:
    bash tests/nixos/test_auto_deploy_command.sh

# Everything CI checks, before you push.
check: build test-infra
    @echo "OK"
