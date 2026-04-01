{
  description = "ilmomasiina dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            nodejs_20
            nodePackages.pnpm
            postgresql_16
          ];

          shellHook = ''
            export PGDATA="$PWD/.pgdata"
            export PGHOST="$PGDATA"
            export PGPORT=5432

            if [ ! -d "$PGDATA" ]; then
              initdb --locale=C --encoding=UTF8 "$PGDATA"
              echo "unix_socket_directories = '$PGDATA'" >> "$PGDATA/postgresql.conf"
            fi
          '';
        };
      });
}
