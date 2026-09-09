# NixOS module: Ilmomasiina application
#
# Runs the app as an OCI container pinned to an image digest, against a
# PostgreSQL instance managed natively by NixOS.
#
# Why a container and not a Nix derivation:
#   Unlike ace-immich, this repo contains application source, so *something*
#   has to build it. Packaging the pnpm monorepo as a derivation would put that
#   build on the server or on a binary cache — and the Attic cache that
#   ace-project-template assumes was decommissioned in September 2026. Consuming
#   the image that .github/workflows/ace-deploy.yml already publishes keeps the
#   server building nothing, which is the property that makes the immich
#   pipeline reliable.
#
# Why the database is not containerised:
#   Postgres under `services.postgresql` gets NixOS' own backup, upgrade and
#   systemd integration, and its data lives at a stable path rather than in a
#   container volume. The app is stateless; this is the only thing worth
#   protecting.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.ilmomasiina;
  image = builtins.fromJSON (builtins.readFile ../image.json);
in
{
  options.services.ilmomasiina = {
    enable = lib.mkEnableOption "Ilmomasiina event signup system";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port the app listens on. Bound to localhost only; Caddy fronts it.";
    };

    database = lib.mkOption {
      type = lib.types.str;
      default = "ilmomasiina";
      description = "PostgreSQL database and role name.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      default = "/etc/secrets/ilmomasiina.env";
      description = ''
        Environment file holding the app's configuration and secrets
        (MAILGUN_API_KEY, FEATHERS_AUTH_SECRET, NEW_EDIT_TOKEN_SECRET, ...).

        Not managed by Nix. Placed out of band — by nixos-anywhere
        --extra-files at install, or over SSH — so it stays out of the
        world-readable Nix store. Must exist before the app starts.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # ---------------------------------------------------------------- #
    # Database
    # ---------------------------------------------------------------- #
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      ensureDatabases = [ cfg.database ];
      ensureUsers = [{
        name = cfg.database;
        ensureDBOwnership = true;
      }];
      # Listen on loopback only. The container reaches this through host
      # networking; nothing off-box should ever connect.
      enableTCPIP = true;
      settings.listen_addresses = lib.mkDefault "127.0.0.1";
      authentication = lib.mkAfter ''
        # The app connects over TCP from the container's host-network
        # namespace, which appears as a loopback connection. trust is safe
        # here because the port is not reachable off-box and the host runs
        # no other workloads.
        host ${cfg.database} ${cfg.database} 127.0.0.1/32 trust
      '';
    };

    # ---------------------------------------------------------------- #
    # Application container
    # ---------------------------------------------------------------- #
    virtualisation.oci-containers = {
      backend = "podman";
      containers.ilmomasiina = {
        # Pinned by digest, not by tag. `:production` moves on every push to
        # dev; if the server tracked it, `nixos-rebuild switch` would be a
        # no-op while the running code silently changed underneath, and
        # rollback would have nothing to roll back to.
        image = "${image.repository}@${image.digest}";

        environmentFiles = [ cfg.environmentFile ];

        environment = {
          # Non-secret settings that belong in version control rather than in
          # the hand-placed env file. Anything here overrides nothing — the
          # env file is read first and these are merged over it, so keep
          # secrets out of this block.
          HOST = "127.0.0.1";
          PORT = toString cfg.port;
          DB_DIALECT = "postgres";
          DB_HOST = "127.0.0.1";
          DB_PORT = "5432";
          DB_USER = cfg.database;
          DB_DATABASE = cfg.database;
          DB_SSL = "false";
        };

        extraOptions = [
          # Host networking so the app can reach Postgres on loopback and bind
          # its port where Caddy expects it, without a bridge or published
          # ports. Acceptable because this host runs exactly one workload.
          "--network=host"
        ];
      };
    };

    # Don't start the app before the database can accept connections.
    systemd.services.podman-ilmomasiina = {
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      serviceConfig = {
        Restart = lib.mkOverride 90 "always";
        RestartSec = "10s";
      };
    };

    # Fail the build rather than deploy a host that cannot start the app.
    assertions = [
      {
        assertion = image.digest != "" && lib.hasPrefix "sha256:" image.digest;
        message = "infra/nixos/image.json must pin a sha256: digest, not a tag.";
      }
    ];
  };
}
