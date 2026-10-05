# From the repository root: nix eval .#checks.x86_64-linux.module-buzz-relay-nginx-options.drvPath
{ nixpkgs, pkgs }:
let
  inherit (nixpkgs) lib;
  evaluate =
    extra:
    (lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ../../modules/buzz-relay/options.nix
        ../../modules/buzz-relay/nginx.nix
        ../../modules/buzz-pair-relay
        ({ pkgs, config, ... }: {
          services.buzz-relay = {
            enable = true;
            package = pkgs.hello;
            nginx = {
              enable = lib.mkDefault true;
              hostName = lib.mkDefault "relay.example.org";
            };
          };
          services.buzz-pair-relay = {
            enable = lib.mkDefault config.services.buzz-relay.pairingRelay.enable;
            package = pkgs.hello;
          };
        })
        extra
      ];
    }).config;
  tls = evaluate { };
  paired = evaluate { services.buzz-relay.pairingRelay.enable = true; };
  plain = evaluate {
    services.buzz-relay.nginx.forceSSL = false;
    services.buzz-relay.pairingRelay.enable = true;
  };
  separate = evaluate {
    services.buzz-relay = {
      adminHost = "ADMIN.example.org";
      pairingRelay = {
        enable = true;
        url = "wss://PAIR.example.org/pair";
      };
    };
    services.buzz-pair-relay = {
      listenAddress = "::";
      port = 5432;
    };
  };
  admin = evaluate {
    services.buzz-relay = {
      adminHost = "ADMIN.example.org";
      pairingRelay = {
        enable = true;
        url = "wss://admin.example.org/pair";
      };
    };
  };
  mixedCase = evaluate {
    services.buzz-relay = {
      nginx.hostName = "RELAY.example.org";
      adminHost = "RELAY.example.org";
      pairingRelay = {
        enable = true;
        url = "wss://Relay.example.org/pair";
      };
    };
  };
  external = evaluate {
    services.buzz-relay.pairingRelay.url = "wss://external.example.org/custom";
    services.buzz-pair-relay.enable = true;
  };
  disabled = evaluate {
    services.buzz-relay.nginx.enable = false;
    services.buzz-relay.pairingRelay.enable = true;
  };
  custom = evaluate {
    services.buzz-relay = {
      relayUrl = "wss://external.example.org";
      media.baseUrl = "https://cdn.example.org/media";
      corsOrigins = [ "https://app.example.org" ];
    };
  };
  invalid =
    extra:
    lib.any (a: !a.assertion && lib.hasInfix "services.buzz-relay" a.message)
      (evaluate extra).assertions;
  locations = c: host: c.services.nginx.virtualHosts.${host}.locations;
  relayLocations = c: locations c "relay.example.org";
in
assert tls.services.buzz-relay.relayUrl == "wss://relay.example.org";
assert tls.services.buzz-relay.media.baseUrl == "https://relay.example.org/media";
assert tls.services.buzz-relay.corsOrigins == [ "https://relay.example.org" ];
assert tls.services.buzz-relay.pairingRelay.url == null;
assert builtins.attrNames (relayLocations tls) == [ "/" ];
assert paired.services.buzz-relay.pairingRelay.url == "wss://relay.example.org/pair";
assert (relayLocations paired)."/".proxyPass == "http://127.0.0.1:3000";
assert (relayLocations paired)."= /pair".proxyPass == "http://127.0.0.1:5000";
assert (relayLocations paired)."= /pair".proxyWebsockets;
assert
  builtins.attrNames (relayLocations paired) == [
    "/"
    "= /pair"
  ];
assert plain.services.buzz-relay.pairingRelay.url == "ws://relay.example.org/pair";
assert plain.services.buzz-relay.relayUrl == "ws://relay.example.org";
assert plain.services.buzz-relay.media.baseUrl == "http://relay.example.org/media";
assert (locations separate "pair.example.org")."= /pair".proxyPass == "http://[::1]:5432";
assert (locations separate "pair.example.org")."/".return == "404";
assert
  builtins.attrNames (locations separate "pair.example.org") == [
    "/"
    "= /pair"
  ];
assert builtins.attrNames (relayLocations separate) == [ "/" ];
assert (locations separate "admin.example.org")."/".proxyPass == "http://127.0.0.1:3000";
assert (locations admin "admin.example.org")."= /pair".proxyPass == "http://127.0.0.1:5000";
assert builtins.attrNames mixedCase.services.nginx.virtualHosts == [ "relay.example.org" ];
assert (relayLocations mixedCase)."= /pair".proxyPass == "http://127.0.0.1:5000";
assert builtins.attrNames external.services.nginx.virtualHosts == [ "relay.example.org" ];
assert builtins.attrNames (relayLocations external) == [ "/" ];
assert external.services.buzz-relay.pairingRelay.url == "wss://external.example.org/custom";
assert disabled.services.buzz-relay.pairingRelay.url == null;
assert !disabled.services.nginx.enable;
assert !(disabled.services.nginx.virtualHosts ? "relay.example.org");
assert custom.services.buzz-relay.relayUrl == "wss://external.example.org";
assert custom.services.buzz-relay.media.baseUrl == "https://cdn.example.org/media";
assert custom.services.buzz-relay.corsOrigins == [ "https://app.example.org" ];
assert invalid { services.buzz-relay.nginx.hostName = null; };
assert invalid { services.buzz-relay.adminHost = "admin.example.org:443"; };
assert invalid {
  services.buzz-relay.pairingRelay.enable = true;
  services.buzz-pair-relay.enable = lib.mkForce false;
};
assert lib.all
  (
    url:
    invalid {
      services.buzz-relay.pairingRelay = {
        enable = true;
        inherit url;
      };
    }
  )
  [
    "wss://relay.example.org"
    "wss://relay.example.org/"
    "wss://relay.example.org/pair/"
    "wss://relay.example.org/socket"
    "wss://relay.example.org/pair/child"
    "wss://relay.example.org:443/pair"
    "wss://relay.example.org/pair?q=1"
    "wss://relay.example.org/pair#fragment"
    "ws://relay.example.org/pair"
    "https://relay.example.org/pair"
    "wss://*.example.org/pair"
  ];
assert invalid {
  services.buzz-relay.nginx.forceSSL = false;
  services.buzz-relay.pairingRelay = {
    enable = true;
    url = "wss://relay.example.org/pair";
  };
};
pkgs.runCommand "buzz-relay-nginx-options" { } "touch $out"
