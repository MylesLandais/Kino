{
  pkgs,
  beam ? pkgs.beam27Packages,
}:
beam.mixRelease {
  pname = "dnd_app";
  version = "0.1.0";
  src = ./.;
  mixFodDeps = beam.fetchMixDeps {
    pname = "dnd_app";
    version = "0.1.0";
    src = ./.;
    hash = "sha256-JRyqdGiDaX+Awdrlmu7cu98QEn1ZLk7+A+fRLGR61f0=";
  };
}
