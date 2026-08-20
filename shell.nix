{
  pkgs ? import <nixpkgs> { },
  beam ? pkgs.beam27Packages,
}:
let
  elixir = beam.elixir_1_17;
in
pkgs.mkShell {
  packages = with pkgs; [
    elixir
    beam.erlang
    nodejs_24
    git
    gnumake
    gcc
    pkg-config
    inotify-tools
  ];

  shellHook = ''
    export ERL_AFLAGS="-kernel shell_history enabled"
  '';
}
