{
  pkgs,
  beam ? pkgs.beam27Packages,
}:
let
  release = beam.mixRelease {
    pname = "image_graph_vectorizer";
    version = "0.1.0";
    src = ./.;
    mixFodDeps = beam.fetchMixDeps {
      pname = "image_graph_vectorizer";
      version = "0.1.0";
      src = ./.;
      hash = "sha256-rcdgCcBGDVYZy/QdV0BzPAsdf1LxDcQ1ZCCCFEWLx0o=";
    };
  };
  mkImage = import ../nix/mkImage.nix { inherit pkgs; };
  dockerImage = mkImage {
    pname = "image_graph_vectorizer";
    package = release;
  };
in
release
// {
  passthru = (release.passthru or { }) // {
    inherit dockerImage;
  };
}
