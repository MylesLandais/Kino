{
  pkgs,
  beam,
  root ? ../.,
}:
let
  allEntries = builtins.readDir root;
  appDirs = builtins.filter (
    name: allEntries.${name} == "directory" && builtins.pathExists (root + "/${name}/default.nix")
  ) (builtins.attrNames allEntries);

  packagesFromDirs = builtins.listToAttrs (
    map (dir: {
      name = dir;
      value = pkgs.callPackage (root + "/${dir}/default.nix") { inherit beam; };
    }) appDirs
  );

  defaultPackage =
    if packagesFromDirs ? kino_app then
      packagesFromDirs.kino_app
    else if appDirs != [ ] then
      packagesFromDirs.${builtins.head appDirs}
    else
      null;
in
packagesFromDirs // (if defaultPackage != null then { default = defaultPackage; } else { })
