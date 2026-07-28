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
  pname = "buzz-desktop-frontend";
  workspace = "buzz";
  sourceDir = "desktop";
  metaDescription = "Frontend bundle embedded in Buzz Desktop";
}
