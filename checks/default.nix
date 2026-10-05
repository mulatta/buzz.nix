{
  pkgs,
  nixpkgs,
  packages,
  devShells,
  nixosModules,
}:
let
  inherit (pkgs) lib;
in
lib.mapAttrs' (name: package: lib.nameValuePair "package-${name}" package) packages
// lib.mapAttrs' (name: shell: lib.nameValuePair "devshell-${name}" shell) devShells
// lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
  module-buzz-pair-relay-options = import ./eval/pair-relay.nix {
    inherit pkgs;
  };
  module-buzz-pair-relay = import ./vm/pair-relay.nix {
    inherit pkgs;
    package = packages.buzz-server-binaries;
    module = nixosModules.buzz-pair-relay;
  };
  module-buzz-push-gateway = import ./eval/push-gateway.nix {
    inherit pkgs;
    module = nixosModules.buzz-push-gateway;
  };
  module-buzz-relay-local-options = import ./eval/relay-local.nix {
    inherit pkgs nixpkgs;
  };
  module-buzz-relay-nginx-options = import ./eval/relay-nginx.nix {
    inherit pkgs nixpkgs;
  };
  module-buzz-relay-local-stack = import ./vm/relay-local-stack.nix {
    inherit pkgs;
    pairPackage = packages.buzz-server-binaries;
    module = nixosModules.buzz-relay;
  };
  module-buzz-relay-options = import ./eval/relay.nix {
    inherit pkgs;
    relayModule = nixosModules.buzz-relay;
  };
  module-evaluation = import ./eval/modules.nix {
    inherit pkgs;
    relayModule = nixosModules.buzz-relay;
    pushModule = nixosModules.buzz-push-gateway;
  };
  module-buzz-relay = import ./vm/relay.nix {
    module = nixosModules.buzz-relay;
    inherit pkgs;
  };
  nixos-buzz-relay-s3-admission-gate = import ./vm/relay-s3-admission.nix {
    inherit lib;
    module = nixosModules.buzz-relay;
    package = packages.buzz-relay;
    inherit pkgs;
  };
  nixos-buzz-relay-rustfs-integration = import ./vm/relay-rustfs.nix {
    inherit lib;
    module = nixosModules.buzz-relay;
    package = packages.buzz-relay;
    inherit pkgs;
  };
}
