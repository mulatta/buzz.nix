{ lib, ... }:
{
  imports = [
    (lib.mkRenamedOptionModule
      [ "services" "buzz-relay" "pairingRelay" "listenAddress" ]
      [ "services" "buzz-pair-relay" "listenAddress" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "buzz-relay" "pairingRelay" "port" ]
      [ "services" "buzz-pair-relay" "port" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "buzz-relay" "pairingRelay" "openFirewall" ]
      [ "services" "buzz-pair-relay" "openFirewall" ]
    )
    ../buzz-pair-relay
    ./options.nix
    ./config.nix
    ./local-services.nix
    ./nginx.nix
  ];
}
