{
  pkgs,
  beam ? pkgs.beam27Packages,
}:
let
  release = beam.mixRelease {
    pname = "dnd_app";
    version = "0.1.0";
    src = ./.;
    mixFodDeps = beam.fetchMixDeps {
      pname = "dnd_app";
      version = "0.1.0";
      src = ./.;
      hash = "sha256-JRyqdGiDaX+Awdrlmu7cu98QEn1ZLk7+A+fRLGR61f0=";
    };
  };
  mkImage = import ../nix/mkImage.nix { inherit pkgs; };
  dockerImage = mkImage {
    pname = "dnd_app";
    package = release;
    exposedPorts = {
      "4000/tcp" = { };
    };
    extraContents = [ pkgs.nodejs_24 ];
  };
in
release
// {
  passthru = (release.passthru or { }) // {
    inherit dockerImage;
  };
}
