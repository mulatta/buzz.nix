{
  flake,
  inputs,
  lib,
  pkgs,
}:

let
  # Only directories with package.nix become flake package outputs.
  # Directories with default.nix provide internal package-scope values.
  publicPackageNames = builtins.attrNames (
    lib.filterAttrs (
      name: type: type == "directory" && builtins.pathExists (./. + "/${name}/package.nix")
    ) (builtins.readDir ./.)
  );

  packageScope = lib.makeScope pkgs.newScope (
    self:
    {
      inherit
        flake
        inputs
        lib
        ;

      source = self.callPackage ./source { };
      buildBuzzFrontend = self.callPackage ./build-buzz-frontend { };
      buildBuzzRust = self.callPackage ./build-buzz-rust { };
    }
    // lib.genAttrs publicPackageNames (name: self.callPackage (./. + "/${name}/package.nix") { })
  );
in
lib.filterAttrs (_name: lib.isDerivation) (
  lib.genAttrs publicPackageNames (name: packageScope.${name})
)
