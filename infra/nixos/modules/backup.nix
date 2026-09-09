# NixOS module: database backups
#
# Nightly logical dumps of the Ilmomasiina database.
#
# Scope, stated plainly: this protects against bad migrations, accidental
# deletion and database corruption. It does NOT protect against loss of the
# server, because the dumps live on the same disk as the data. That is the same
# gap ace-immich records as its largest open risk. The database is ~9 MB, so
# copying it off-box is cheap — `offsiteCommand` is the hook for that, and
# until it is set, `just backup-status` reports the backup as local-only.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.ilmomasiinaBackup;
in
{
  options.services.ilmomasiinaBackup = {
    enable = lib.mkEnableOption "nightly Ilmomasiina database backups";

    database = lib.mkOption {
      type = lib.types.str;
      default = "ilmomasiina";
      description = "Database to dump.";
    };

    directory = lib.mkOption {
      type = lib.types.path;
      default = "/var/backup/ilmomasiina";
      description = "Where dumps are written.";
    };

    keepDays = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Dumps older than this are deleted after a successful run.";
    };

    startAt = lib.mkOption {
      type = lib.types.str;
      default = "03:30";
      description = "systemd OnCalendar expression for the nightly dump.";
    };

    offsiteCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "restic backup /var/backup/ilmomasiina";
      description = ''
        Optional command run after a successful dump, with $DUMP_FILE set to
        the file just written. Until this is set, backups never leave the
        server and do not survive its loss.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.directory} 0700 postgres postgres -"
    ];

    systemd.services.ilmomasiina-backup = {
      description = "Dump the Ilmomasiina database";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      startAt = cfg.startAt;

      path = [ config.services.postgresql.package pkgs.gzip pkgs.coreutils pkgs.findutils ];

      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
      };

      script = ''
        set -euo pipefail

        stamp=$(date -u +%Y%m%dT%H%M%SZ)
        export DUMP_FILE="${cfg.directory}/${cfg.database}-$stamp.sql.gz"

        # Write to a temporary name and rename only on success, so an
        # interrupted dump can never be mistaken for a usable backup.
        pg_dump --no-owner --no-privileges "${cfg.database}" \
          | gzip -9 > "$DUMP_FILE.partial"
        mv "$DUMP_FILE.partial" "$DUMP_FILE"

        # A dump that restores to nothing is worse than no dump, because it
        # looks like protection. gzip -t catches truncation and corruption.
        gzip -t "$DUMP_FILE"

        echo "wrote $DUMP_FILE ($(stat -c %s "$DUMP_FILE") bytes)"

        ${lib.optionalString (cfg.offsiteCommand != null) ''
          ${cfg.offsiteCommand}
        ''}

        # Prune only after everything above succeeded, so a broken dump run
        # never expires the last good backup.
        find "${cfg.directory}" -name '${cfg.database}-*.sql.gz' \
          -mtime +${toString cfg.keepDays} -delete
        find "${cfg.directory}" -name '*.partial' -mtime +1 -delete
      '';
    };

    systemd.timers.ilmomasiina-backup.timerConfig = {
      Persistent = true;
      RandomizedDelaySec = "5min";
    };
  };
}
