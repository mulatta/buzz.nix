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
  pname = "buzz-admin-web";
  workspace = "buzz-admin-web";
  sourceDir = "admin-web";
  metaDescription = "Administration interface for Buzz relay";
}
