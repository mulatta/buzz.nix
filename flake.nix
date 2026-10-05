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
        import ./checks {
          pkgs = pkgsFor.${system};
          inherit nixpkgs;
          packages = packages.${system};
          devShells = self.devShells.${system};
          inherit (self) nixosModules;
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
        buzz-pair-relay =
          { pkgs, ... }:
          {
            imports = [ ./modules/buzz-pair-relay ];
            services.buzz-pair-relay.package =
              lib.mkOptionDefault
                packages.${pkgs.stdenv.hostPlatform.system}.buzz-server-binaries;
          };
        buzz-relay =
          { pkgs, ... }:
          {
            imports = [
              ./modules/buzz-relay
              self.nixosModules.buzz-pair-relay
            ];
            services.buzz-relay.package = lib.mkDefault packages.${pkgs.stdenv.hostPlatform.system}.buzz-relay;
          };
        buzz-push-gateway =
          { pkgs, ... }:
          {
            imports = [ ./modules/buzz-push-gateway ];
            services.buzz-push-gateway.package =
              lib.mkDefault
                packages.${pkgs.stdenv.hostPlatform.system}.buzz-push-gateway;
          };
        default = self.nixosModules.buzz-relay;
      };
    };
}
