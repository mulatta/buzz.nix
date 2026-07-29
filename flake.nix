{
  description = "buzz: A hive mind communication platform";

  nixConfig = {
    allow-import-from-derivation = false;
    extra-substituters = [ "https://cache.mulatta.io" ];
    extra-trusted-public-keys = [ "cache.mulatta.io-1:DrV+Oy2azNyVKM7ihhD1QoOetRUnW+1G6RWToUpSO4U=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      rust-overlay,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      eachSystem = lib.genAttrs systems;

      pkgsFor = eachSystem (
        system:
        import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        }
      );

      packageNames = builtins.attrNames (
        lib.filterAttrs (
          name: type: type == "directory" && builtins.pathExists (./packages + "/${name}/package.nix")
        ) (builtins.readDir ./packages)
      );

      mkPackagesFor =
        pkgs:
        let
          scope = lib.makeScope pkgs.newScope (
            self:
            {
              inherit inputs lib;
              flake = self;

              source = self.callPackage ./packages/source { };
              buildBuzzFrontend = self.callPackage ./packages/build-buzz-frontend { };
              buildBuzzRust = self.callPackage ./packages/build-buzz-rust { };
            }
            // lib.genAttrs packageNames (name: self.callPackage (./packages + "/${name}/package.nix") { })
          );
        in
        lib.filterAttrs (_name: lib.isDerivation) (lib.genAttrs packageNames (name: scope.${name}));

      packages = eachSystem (system: mkPackagesFor pkgsFor.${system});
    in
    {
      inherit packages;

      checks = eachSystem (
        system:
        lib.mapAttrs' (name: package: lib.nameValuePair "package-${name}" package) packages.${system}
        // {
          devshell-default = self.devShells.${system}.default;
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          module-buzz-relay = import ./modules/buzz-relay/nixos-test.nix {
            module = self.nixosModules.buzz-relay;
            pkgs = pkgsFor.${system};
          };
          nixos-buzz-relay-rustfs-gate = import ./tests/buzz-relay.nix {
            inherit lib;
            module = self.nixosModules.buzz-relay;
            package = self.packages.${system}.buzz-relay;
            pkgs = pkgsFor.${system};
          };
        }
      );

      devShells = eachSystem (system: {
        default = import ./devshell.nix {
          pkgs = pkgsFor.${system};
          formatter = packages.${system}.formatter;
        };
      });

      formatter = eachSystem (system: packages.${system}.formatter);

      nixosModules = {
        buzz-relay =
          { pkgs, ... }:
          {
            imports = [ ./modules/buzz-relay ];
            services.buzz-relay.package = lib.mkDefault packages.${pkgs.stdenv.hostPlatform.system}.buzz-relay;
          };
        default = self.nixosModules.buzz-relay;
      };
    };
}
