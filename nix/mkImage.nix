{ pkgs }:
{
  pname,
  package,
  bin ? pname,
  tag ? "latest",
  exposedPorts ? { },
  extraContents ? [ ],
  env ? [ ],
  cmd ? [
    "${package}/bin/${bin}"
    "start"
  ],
}:
pkgs.dockerTools.buildLayeredImage {
  name = pname;
  tag = tag;
  contents = [
    package
    pkgs.cacert
  ]
  ++ extraContents;
  config = {
    Cmd = cmd;
    ExposedPorts = exposedPorts;
    Env = [
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "LANG=C.UTF-8"
      "LC_ALL=C.UTF-8"
    ]
    ++ env;
    WorkingDir = "/";
  };
  created = "now";
}
