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
          # Node must track .nvmrc, which CI reads via actions/setup-node.
          # A mismatch here means the dev shell and CI build on different
          # majors. nodejs_20 was removed from nixpkgs on its 2026-04-30 EOL,
          # which broke this shell outright until it was bumped.
          packages = with pkgs; [
            nodejs_24
            pnpm
            postgresql_16

            # Operational tooling — see justfile.
            just
            jq
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
