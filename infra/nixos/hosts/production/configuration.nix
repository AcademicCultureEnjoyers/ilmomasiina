# Ilmomasiina production host
#
# Runs signup.academicculture.org:
#   - Ilmomasiina   (OCI container from GHCR, pinned by digest + native Postgres)
#   - Caddy         (TLS reverse proxy, 443 -> 3000)
#   - Tailscale     (administrative access only — nothing in the deploy path
#                    depends on it)
#   - Auto-deploy   (pulls the `deploy` branch from GitHub on a timer)
#   - Backups       (nightly pg_dump; see modules/backup.nix for what this
#                    does and does not protect against)
#
# This host depends on no other server at runtime. The NixOS closure comes from
# cache.nixos.org and the app image from GHCR; the only credentials it holds
# are a read-only GitHub deploy key and the app's env file, both placed at
# install time. See docs/architecture/production.md.
{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/disk.nix
    ../../modules/tailscale.nix
    ../../modules/auto-deploy.nix
    ../../modules/caddy.nix
    ../../modules/ilmomasiina.nix
    ../../modules/backup.nix
  ];

  # ------------------------------------------------------------------ #
  # Application
  # ------------------------------------------------------------------ #
  services.ilmomasiina = {
    enable = true;
    port = 3000;
  };

  services.ilmomasiinaBackup = {
    enable = true;
    # Nightly at 03:30 UTC — well clear of the 15-minute deploy timer's busiest
    # hours and of Ilmomasiina's own signup-opening traffic, which clusters
    # around midday.
    startAt = "03:30";
  };

  # ------------------------------------------------------------------ #
  # Auto-deploy
  # ------------------------------------------------------------------ #
  services.autoDeploy = {
    enable = true;
    flake = "git+ssh://git@github.com/AcademicCultureEnjoyers/ilmomasiina?ref=deploy&dir=infra/nixos";
  };

  # ------------------------------------------------------------------ #
  # Base system
  # ------------------------------------------------------------------ #
  networking = {
    hostName = "ilmomasiina";
    useDHCP = lib.mkDefault true;
  };

  time.timeZone = "Europe/Helsinki";

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      # Root is the only account and is key-only, but disable password and
      # keyboard-interactive auth outright so a future user account cannot
      # quietly reintroduce password logins on an internet-facing host.
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPX8MkZCulQ+SrEHxX39T+qQzYcqr5+zoYeDVxeLFI7H ace-infra-deploy"
  ];

  # Keep enough generations to roll back through a bad week of deploys, but not
  # so many that the root disk fills with old closures.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.settings.auto-optimise-store = true;

  # Old container images are not covered by nix gc — podman keeps every digest
  # the server has ever pulled, and this host pulls a new one on every deploy.
  # nixpkgs already provides the unit; defining our own `podman-prune` service
  # collides with it.
  virtualisation.podman.autoPrune = {
    enable = true;
    dates = "weekly";
    # Images only. The default also prunes volumes, and Postgres is native
    # here — but a stray volume prune is not something to leave to chance on
    # the host holding the signup database.
    flags = [ "--all" "--filter" "until=720h" ];
  };

  boot.loader.grub.enable = lib.mkDefault true;

  system.stateVersion = "24.11";
}
