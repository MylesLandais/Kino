{
  pkgs,
  beam ? pkgs.beam27Packages,
}:
let
  release = beam.mixRelease {
    pname = "kino_app";
    version = "0.1.0";
    src = ./.;
    mixFodDeps = beam.fetchMixDeps {
      pname = "kino_app";
      version = "0.1.0";
      src = ./.;
      hash = "sha256-YKcFGXS8sMs12Y/R0pOYQ4waAf8ASj6fg8bFC/C+mIM=";
    };
    # Use Nix-provided binaries in the hermetic build (avoids stub-ld generic downloads)
    MIX_ESBUILD_PATH = "${pkgs.esbuild}/bin/esbuild";
    MIX_TAILWIND_PATH = "${pkgs.tailwindcss_4}/bin/tailwindcss";
  };
  mkImage = import ../nix/mkImage.nix { inherit pkgs; };
  dockerImage = mkImage {
    pname = "kino_app";
    package = release;
    bin = "kino";
    exposedPorts = {
      "4000/tcp" = { };
    };
    extraContents = [
      pkgs.nodejs_24
      pkgs.yt-dlp
      pkgs.ffmpeg
    ];
    env = [
      "KINO_YTDLP_BIN=/bin/yt-dlp"
    ];
  };
in
release
// {
  passthru = (release.passthru or { }) // {
    inherit dockerImage;
  };
}
