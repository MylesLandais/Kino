{
  pkgs,
  beam ? pkgs.beam27Packages,
}:
beam.mixRelease {
  pname = "image_graph_vectorizer";
  version = "0.1.0";
  src = ./.;
  mixFodDeps = beam.fetchMixDeps {
    pname = "image_graph_vectorizer";
    version = "0.1.0";
    src = ./.;
    hash = "sha256-rcdgCcBGDVYZy/QdV0BzPAsdf1LxDcQ1ZCCCFEWLx0o=";
  };
}
