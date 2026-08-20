{
  pkgs,
  beam ? pkgs.beam27Packages,
}:
beam.mixRelease {
  pname = "harness";
  version = "0.1.0";
  src = ./.;
  mixFodDeps = beam.fetchMixDeps {
    pname = "harness";
    version = "0.1.0";
    src = ./.;
    hash = "sha256-D5/44zUiwyqdwGVf36upCVEeZZbl6s29/5ENoWSs9SQ=";
  };
}
