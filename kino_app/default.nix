{
  pkgs,
  beam ? pkgs.beam27Packages,
}:
beam.mixRelease {
  pname = "kino_app";
  version = "0.1.0";
  src = ./.;
  mixFodDeps = beam.fetchMixDeps {
    pname = "kino_app";
    version = "0.1.0";
    src = ./.;
    hash = "sha256-YKcFGXS8sMs12Y/R0pOYQ4waAf8ASj6fg8bFC/C+mIM=";
  };
}
