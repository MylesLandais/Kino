{
  pkgs,
  beam ? pkgs.beam27Packages,
}:
let
  release = beam.mixRelease {
    pname = "harness";
    version = "0.1.0";
    src = ./.;
    mixFodDeps = beam.fetchMixDeps {
      pname = "harness";
      version = "0.1.0";
      src = ./.;
      hash = "sha256-D5/44zUiwyqdwGVf36upCVEeZZbl6s29/5ENoWSs9SQ=";
    };
  };
  mkImage = import ../nix/mkImage.nix { inherit pkgs; };
  dockerImage = mkImage {
    pname = "harness";
    package = release;
  };
in
release
// {
  passthru = (release.passthru or { }) // {
    inherit dockerImage;
  };
}
