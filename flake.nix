{
  description = "Kino theater — NixOS development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            beamPackages.elixir
            esbuild
            git
            inotify-tools
            postgresql_17
            nodejs_24
            tailwindcss_4
            yt-dlp
          ];

          shellHook = ''
            export MIX_ESBUILD_PATH="${pkgs.esbuild}/bin/esbuild"
            export MIX_TAILWIND_PATH="${pkgs.tailwindcss_4}/bin/tailwindcss"
            export KINO_NIX_SHELL=1
            echo "Kino dev shell — run ./launch.sh"
          '';
        };
      });
}
