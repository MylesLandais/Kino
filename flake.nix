{
  description = "Kino - Elixir dev shell + per-app Mix builds (auto-discovered)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          beam = pkgs.beam27Packages;
        in
        {
          packages = import ./nix/packages.nix { inherit pkgs beam; };

          devShells.default = import ./shell.nix { inherit pkgs beam; };

          formatter = pkgs.nixfmt-tree;
        }
      );
}
