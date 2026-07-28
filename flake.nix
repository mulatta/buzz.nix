{
  description = "buzz: A hive mind communication platform";

  nixConfig = {
    allow-import-from-derivation = false;
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
      baseLib = nixpkgs.lib;
      lib = baseLib.extend (import ./lib);

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

    in
    {
      packages = eachSystem (
        system:
        import ./packages {
          inherit inputs lib;
          flake = self;
          pkgs = pkgsFor.${system};
        }
      );

      checks = eachSystem (
        system:
        lib.mapAttrs' (name: package: lib.nameValuePair "package-${name}" package) self.packages.${system}
        // {
          devshell-default = self.devShells.${system}.default;
          formatting = self.packages.${system}.formatter.passthru.tests.check;
        }
      );

      devShells = eachSystem (system: {
        default = import ./devshell.nix {
          pkgs = pkgsFor.${system};
          formatter = self.packages.${system}.formatter;
        };
      });

      formatter = eachSystem (system: self.packages.${system}.formatter);
    };
}
