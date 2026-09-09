#!/usr/bin/env bash
# Verify the auto-deploy unit invokes nixos-rebuild with the flake ref as a
# single, intact argument.
#
# Regression test. The flake ref contains two query parameters
# (`?ref=deploy&dir=infra/nixos`). nixpkgs' system.autoUpgrade interpolates the
# ref into bash unquoted, so the bare `&` backgrounded the rebuild and turned
# `dir=infra/nixos` into a variable assignment. The unit exited 0 in
# milliseconds having deployed nothing, and Type=oneshot reaped the
# backgrounded job — a deploy that reports success and never happens.
#
# Asserting on the script text alone is not enough; this runs the script with a
# stub in place of nixos-rebuild and inspects the arguments it actually
# receives.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v nix >/dev/null 2>&1; then
    echo "  SKIP: nix not available"
    exit 0
fi

# Includes the #production attribute: nixos-rebuild otherwise infers the
# configuration name from the hostname (`ilmomasiina`), which does not exist in
# the flake and fails the deploy.
EXPECTED_FLAKE="git+ssh://git@github.com/AcademicCultureEnjoyers/ilmomasiina?ref=deploy&dir=infra/nixos#production"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

script="$(nix eval --raw \
    "$REPO_ROOT/infra/nixos#nixosConfigurations.production.config.systemd.services.nixos-upgrade.script" \
    2>/dev/null)"

if [ -z "$script" ]; then
    echo "FAIL: could not evaluate nixos-upgrade.script" >&2
    exit 1
fi

# Stub stands in for nixos-rebuild and reports the argv it was handed.
cat > "$workdir/stub" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@"
STUB
chmod +x "$workdir/stub"

# Swap the nixos-rebuild store path for the stub, preserving everything else.
printf '%s\n' "$script" \
    | sed "s|exec /nix/store/[^ ]*/bin/nixos-rebuild|exec $workdir/stub|" \
    > "$workdir/run.sh"

if ! grep -q "$workdir/stub" "$workdir/run.sh"; then
    echo "FAIL: could not substitute the nixos-rebuild invocation" >&2
    echo "script was:" >&2
    printf '%s\n' "$script" >&2
    exit 1
fi

bash "$workdir/run.sh" > "$workdir/args.txt" 2>/dev/null

# The whole ref must arrive as one argument. Under the old bug the argument
# list stopped at `...?ref=deploy` and `dir=infra/nixos` vanished entirely.
if ! grep -Fxq -- "$EXPECTED_FLAKE" "$workdir/args.txt"; then
    echo "FAIL: flake ref was not passed as a single intact argument" >&2
    echo "expected: $EXPECTED_FLAKE" >&2
    echo "got arguments:" >&2
    sed 's/^/  /' "$workdir/args.txt" >&2
    exit 1
fi

# `switch` — not `boot`, which would defer activation to the next reboot.
if ! grep -Fxq -- "switch" "$workdir/args.txt"; then
    echo "FAIL: expected 'switch' operation" >&2
    exit 1
fi

# --refresh, or the timer re-resolves the branch only once per tarball-ttl.
if ! grep -Fxq -- "--refresh" "$workdir/args.txt"; then
    echo "FAIL: expected '--refresh'" >&2
    exit 1
fi

# --upgrade would update flake inputs, drifting off the committed flake.lock.
if grep -Fxq -- "--upgrade" "$workdir/args.txt"; then
    echo "FAIL: '--upgrade' present; set system.autoUpgrade.upgrade = false" >&2
    exit 1
fi

echo "  PASS: auto-deploy command"
