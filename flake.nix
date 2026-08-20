{
  description = "Kino theater — FHS Nix development shell with PostgreSQL 19 SQL/PGQ and OpenBao";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;

        # Shared libraries that mix/npm/erlang native bits and unpatched
        # binaries expect under an FHS layout. Missing any of these is the
        # usual "error while loading shared libraries" failure on Nix.
        fhsLibs = with pkgs; [
          stdenv.cc.cc
          stdenv.cc.cc.lib
          glibc
          zlib
          openssl
          openssl.out
          libffi
          libxcrypt
          ncurses
          readline
          curl
          icu
          libxml2
          xz
          bzip2
          zstd
          sqlite
          util-linux
          libuuid
          gmp
          libunwind
          krb5
          expat
          libseccomp
          acl
          attr
          libcap
          keyutils
          pcre2
          libidn2
          nghttp2
          dbus
          systemd
          glib
        ];

        fhsTools = with pkgs; [
          bashInteractive
          coreutils
          findutils
          gnugrep
          gnused
          gawk
          gnumake
          gcc
          binutils
          pkg-config
          git
          cacert
          unzip
          gnutar
          gzip
          which
          file
          procps
          ripgrep
          inotify-tools
          python3
          patchelf
          glibcLocales
          beamPackages.elixir
          beamPackages.erlang
          nodejs_24
          postgresql_19
          esbuild
          tailwindcss_4
          yt-dlp
          openbao
        ];

        kinoProfile = ''
          export KINO_FHS=1
          export KINO_NIX_SHELL=1
          export MIX_ESBUILD_PATH="${pkgs.esbuild}/bin/esbuild"
          export MIX_TAILWIND_PATH="${pkgs.tailwindcss_4}/bin/tailwindcss"
          export KINO_YTDLP_BIN="${pkgs.yt-dlp}/bin/yt-dlp"
          export LANG=C.UTF-8
          export LC_ALL=C.UTF-8
          export LOCALE_ARCHIVE="${pkgs.glibcLocales}/lib/locale/locale-archive"
          export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          export GIT_SSL_CAINFO="$SSL_CERT_FILE"
          export CURL_CA_BUNDLE="$SSL_CERT_FILE"
          export ERL_AFLAGS="-kernel shell_history enabled"
          export NIX_LD="${pkgs.stdenv.cc.bintools.dynamicLinker}"
          export NIX_LD_LIBRARY_PATH="${lib.makeLibraryPath fhsLibs}"
          export KINO_PGDATA="''${KINO_PGDATA:-''${XDG_STATE_HOME:-$HOME/.local/state}/kino/postgresql}"
          export KINO_PGHOST="''${KINO_PGHOST:-''${XDG_STATE_HOME:-$HOME/.local/state}/kino/postgresql-run}"
          export PGHOST="''${PGHOST:-$KINO_PGHOST}"
          export PGPORT="''${PGPORT:-5432}"
          export PGDATA="''${PGDATA:-$KINO_PGDATA}"
        '';

        kinoFhs = pkgs.buildFHSEnv {
          name = "kino-fhs";
          targetPkgs = _pkgs: fhsTools ++ fhsLibs;
          extraOutputsToInstall = [ "dev" "out" ];
          profile = kinoProfile;
          # nix run .#fhs          -> interactive bash
          # nix run .#fhs -- cmd   -> cmd, with FHS /lib and /usr/lib populated
          runScript = pkgs.writeShellScript "kino-fhs-run" ''
            if [ "$#" -eq 0 ]; then
              exec bash
            fi
            exec "$@"
          '';
        };
      in {
        packages.fhs = kinoFhs;
        packages.default = kinoFhs;

        # Interactive `nix develop` enters the same FHS userspace.
        # Non-interactive commands should use `nix run .#fhs -- ...`
        # so arguments are not swallowed by an extra bash.
        devShells.default = kinoFhs.env;
      });
}
