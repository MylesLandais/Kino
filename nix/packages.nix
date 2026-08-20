{
  pkgs,
  beam,
  root ? ../.,
}:
let
  allEntries = builtins.readDir root;
  # Exclude helper dirs that may have a default.nix but are not apps
  ignoredDirs = [ "nix" ];
  appDirs = builtins.filter (
    name:
    allEntries.${name} == "directory"
    && !(builtins.elem name ignoredDirs)
    && builtins.pathExists (root + "/${name}/default.nix")
  ) (builtins.attrNames allEntries);

  packagesFromDirs = builtins.listToAttrs (
    map (dir: {
      name = dir;
      value = pkgs.callPackage (root + "/${dir}/default.nix") { inherit beam; };
    }) appDirs
  );

  # Docker images are defined inside each default.nix via mkImage and exposed as passthru.dockerImage.
  # This keeps per-app flexibility (extraContents like nodejs, etc.) while still being
  # discoverable centrally for `nix build .#pname-docker` / `nix build .#pname-dockerImage`.
  dockerImagesList = builtins.filter (x: x != null) (
    map (
      dir:
      let
        pkg = packagesFromDirs.${dir};
        img = pkg.passthru.dockerImage or null;
      in
      if img != null then
        {
          name = "${dir}-docker";
          value = img;
        }
      else
        null
    ) appDirs
  );

  dockerImages = builtins.listToAttrs dockerImagesList;

  dockerImagesAlias = builtins.listToAttrs (
    map (img: {
      name = "${img.name}Image";
      value = img.value;
    }) dockerImagesList
  );

  defaultPackage =
    if packagesFromDirs ? kino_app then
      packagesFromDirs.kino_app
    else if appDirs != [ ] then
      packagesFromDirs.${builtins.head appDirs}
    else
      null;
in
packagesFromDirs
// dockerImages
// dockerImagesAlias
// (if defaultPackage != null then { default = defaultPackage; } else { })
