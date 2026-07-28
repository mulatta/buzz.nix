{
  lib,
  pkgs,
  pnpmDeps,
  source,
}:

let
  mkBuzzFrontend = lib.buzz.mkBuzzFrontendPackage {
    inherit
      lib
      pkgs
      pnpmDeps
      source
      ;
  };
in
mkBuzzFrontend {
  pname = "buzz-web";
  workspace = "buzz-web";
  sourceDir = "web";
  metaDescription = "Web client for Buzz relay";
}
