{
  lib,
  pkgs,
}:

let
  # Only directories with package.nix become flake package outputs.
  # Directories with default.nix are internal scope derivations.
  publicPackageNames = builtins.attrNames (
    lib.filterAttrs (
      name: type: type == "directory" && builtins.pathExists (./. + "/${name}/package.nix")
    ) (builtins.readDir ./.)
  );

  packageScope = lib.makeScope pkgs.newScope (
    self:
    {
      # Use extended flake lib so package.nix files can access lib.buzz helpers.
      inherit lib;

      source = self.callPackage ./source { };
      pnpmDeps = self.callPackage ./pnpm-deps {
        inherit (self) source;
      };
    }
    // lib.genAttrs publicPackageNames (name: self.callPackage (./. + "/${name}/package.nix") { })
  );
in
lib.filterAttrs (_name: lib.isDerivation) (
  lib.genAttrs publicPackageNames (name: packageScope.${name})
)
