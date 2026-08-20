{
  pkgs ? import <nixpkgs> { },
  beam ? pkgs.beam27Packages,
}:
let
  elixir = beam.elixir_1_17;
  dockerLoad = pkgs.writeShellScriptBin "docker-load" (builtins.readFile ./scripts/docker-load.sh);
in
pkgs.mkShell {
  packages = with pkgs; [
    elixir
    beam.erlang
    nodejs_24
    postgresql_19
    tailwindcss_4
    esbuild
    yt-dlp
    ffmpeg
    cacert
    docker
    dockerLoad
    git
    gnumake
    gcc
    pkg-config
    inotify-tools
  ];

  shellHook = ''
    export ERL_AFLAGS="-kernel shell_history enabled"
    export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    export GIT_SSL_CAINFO="$SSL_CERT_FILE"
    export CURL_CA_BUNDLE="$SSL_CERT_FILE"
    export KINO_YTDLP_BIN="${pkgs.yt-dlp}/bin/yt-dlp"
    # Replicate scripts/pg-env.sh so every `nix develop` has a usable Postgres socket.
    # The launch scripts also source pg-env.sh, but the dev shell itself needs it for `mix test`.
    export XDG_STATE_HOME="''${XDG_STATE_HOME:-$HOME/.local/state}"
    export PGDATA="''${KINO_PGDATA:-''${PGDATA:-$XDG_STATE_HOME/kino/postgresql}}"
    export PGHOST="''${KINO_PGHOST:-''${PGHOST:-$XDG_STATE_HOME/kino/postgresql-run}}"
    export PGPORT="''${PGPORT:-5432}"
    export KINO_PGDATA="$PGDATA"
    export KINO_PGHOST="$PGHOST"
    export PGDATA
    export PGHOST
    export PGPORT
    # Use Nix-provided esbuild/tailwind binaries on NixOS (avoids stub-ld generic linux binaries)
    export MIX_ESBUILD_PATH="${pkgs.esbuild}/bin/esbuild"
    export MIX_TAILWIND_PATH="${pkgs.tailwindcss_4}/bin/tailwindcss"
  '';
}
