# NixOS module: pull-based auto-deploy
#
# The server deploys itself. On a timer it fetches this repo's `deploy` branch
# from GitHub and runs `nixos-rebuild switch` against the flake in infra/nixos.
#
# Why pull and not push:
#   - Nothing needs inbound access to this host. CI has no SSH key, no token,
#     and no route to production.
#   - The application ships as a prebuilt container image from GHCR, pinned by
#     digest in image.json, so the NixOS closure itself comes entirely from
#     cache.nixos.org. The server builds essentially nothing.
#   - No binary cache or secrets server has to exist for a deploy to work.
#     ace-project-template assumes an Attic cache; that server was
#     decommissioned in September 2026, so this deliberately does not use one.
#
# The `deploy` branch is advanced by CI only after tests pass, so the timer
# tracks tested commits rather than whatever last landed on main.
#
# Built on nixpkgs' system.autoUpgrade, which already handles the awkward part:
# running switch-to-configuration from inside a unit that the switch may itself
# restart.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.autoDeploy;
in
{
  options.services.autoDeploy = {
    enable = lib.mkEnableOption "pull-based auto-deploy from GitHub";

    flake = lib.mkOption {
      type = lib.types.str;
      description = "Flake reference to deploy. Must point at the NixOS flake, including its subdirectory.";
      example = "git+ssh://git@github.com/org/repo?ref=deploy&dir=infra/nixos";
    };

    configuration = lib.mkOption {
      type = lib.types.str;
      default = "production";
      description = ''
        Name of the attribute under `nixosConfigurations` to deploy.

        Must be set explicitly: nixos-rebuild otherwise infers it from the
        hostname, and this host is `ilmomasiina` while the configuration is
        `production` — so the default would look for a nonexistent attribute.
      '';
    };

    deployKeyFile = lib.mkOption {
      type = lib.types.path;
      default = "/etc/secrets/github-deploy-key";
      description = ''
        Read-only GitHub deploy key used to fetch the flake.

        Not managed by Nix — it is placed out of band (by nixos-anywhere
        --extra-files at install, or over SSH) and must exist before the first
        timer run. Keeping it off the Nix store keeps it out of world-readable
        paths.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "*:0/15";
      description = "systemd OnCalendar expression for how often to check for a new commit.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Pin GitHub's host keys rather than trusting on first use. Sourced from
    # https://api.github.com/meta.
    programs.ssh.knownHosts.github = {
      hostNames = [ "github.com" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    };

    system.autoUpgrade = {
      enable = true;
      flake = cfg.flake;
      dates = cfg.interval;

      # nixpkgs already adds `--refresh --flake <ref>` for us when `flake` is
      # set, so we add no flags of our own. Note that `flags` is a list option:
      # a definition here would be *merged* with the module's, not replace it,
      # which is how you end up with a duplicated `--refresh`.

      # Suppress the `--upgrade` flag nixpkgs otherwise appends. With a flake
      # it would update inputs on every run, so the server would drift off the
      # committed flake.lock instead of deploying the pinned closure.
      upgrade = false;

      # Reboots would interrupt photo serving for a kernel update we did not
      # ask for. Kernel changes are applied on the next manual reboot.
      allowReboot = false;

      randomizedDelaySec = "5min";
    };

    systemd.services.nixos-upgrade = {
      environment.GIT_SSH_COMMAND =
        "${pkgs.openssh}/bin/ssh -i ${cfg.deployKeyFile} -o IdentitiesOnly=yes";

      # Nix shells out to git to fetch a git+ssh flake ref.
      path = [ pkgs.git pkgs.openssh ];

      # Own the command rather than let nixpkgs assemble it.
      #
      # nixpkgs builds the script as `nixos-rebuild switch ${toString flags}`,
      # interpolating the flake ref into bash *unquoted*. Our ref needs two
      # query parameters (`?ref=deploy&dir=infra/nixos`), and the bare `&` makes
      # bash background the rebuild and read `dir=infra/nixos` as a variable
      # assignment. The unit then exits 0 in milliseconds having done nothing,
      # and Type=oneshot reaps the backgrounded job — a deploy that reports
      # success and silently never happens.
      #
      # Quoting the ref here fixes it and keeps the failure mode impossible to
      # reintroduce by editing the flake string. Covered by
      # tests/nixos/test_auto_deploy_command.sh.
      script = lib.mkForce ''
        exec ${config.system.build.nixos-rebuild}/bin/nixos-rebuild \
          ${config.system.autoUpgrade.operation} --refresh \
          --flake "${cfg.flake}#${cfg.configuration}"
      '';

      serviceConfig = {
        # A deploy that wedges must not hold the timer forever.
        TimeoutStartSec = "30min";
      };
    };

    # Fail the build rather than deploy a host that cannot fetch its own config.
    assertions = [
      {
        assertion = cfg.flake != "";
        message = "services.autoDeploy.flake must be set when auto-deploy is enabled.";
      }
    ];
  };
}
