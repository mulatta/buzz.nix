{
  pkgs,
  module ? ./default.nix,
}:
let
  inherit (pkgs) lib;
  evaluate =
    settings:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        module
        {
          boot.isContainer = true;
          system.stateVersion = "25.11";
          services.buzz-pair-relay = settings;
        }
      ];
    });
  disabled = evaluate { };
  enabled =
    settings:
    (evaluate (
      {
        enable = true;
        package = pkgs.hello;
      }
      // settings
    )).config;
  base = enabled { };
  public = enabled {
    listenAddress = "0.0.0.0";
    port = 443;
    openFirewall = true;
  };
  ipv6 = enabled { listenAddress = "::1"; };
  bracketed = enabled { listenAddress = "[::1]"; };
  service = base.systemd.services.buzz-pair-relay;
  missing = evaluate { enable = true; };
in
assert !(disabled.config.systemd.services ? buzz-pair-relay);
assert !(disabled.options.services.buzz-pair-relay.package ? default);
assert
  !(builtins.tryEval missing.config.systemd.services.buzz-pair-relay.serviceConfig.ExecStart).success;
assert lib.all (x: x.assertion) base.assertions;
assert service.serviceConfig.ExecStart == "${pkgs.hello}/bin/buzz-pair-relay";
assert service.environment.BUZZ_PAIR_RELAY_BIND_ADDR == "127.0.0.1:5000";
assert ipv6.systemd.services.buzz-pair-relay.environment.BUZZ_PAIR_RELAY_BIND_ADDR == "[::1]:5000";
assert
  bracketed.systemd.services.buzz-pair-relay.environment.BUZZ_PAIR_RELAY_BIND_ADDR == "[::1]:5000";
assert
  public.systemd.services.buzz-pair-relay.environment.BUZZ_PAIR_RELAY_BIND_ADDR == "0.0.0.0:443";
assert !(builtins.elem 5000 base.networking.firewall.allowedTCPPorts);
assert builtins.elem 443 public.networking.firewall.allowedTCPPorts;
assert service.serviceConfig.DynamicUser;
assert service.serviceConfig.ProtectSystem == "strict";
assert service.serviceConfig.NoNewPrivileges;
assert service.serviceConfig.PrivateDevices;
assert service.serviceConfig.MemoryDenyWriteExecute;
assert service.serviceConfig.CapabilityBoundingSet == "";
assert service.serviceConfig.AmbientCapabilities == "";
assert
  public.systemd.services.buzz-pair-relay.serviceConfig.CapabilityBoundingSet
  == "CAP_NET_BIND_SERVICE";
assert
  public.systemd.services.buzz-pair-relay.serviceConfig.AmbientCapabilities == "CAP_NET_BIND_SERVICE";
assert !(base.systemd.services ? buzz-relay);
assert !base.services.postgresql.enable;
assert base.services.redis.servers == { };
assert !(service.environment ? DATABASE_URL);
assert !(service.environment ? REDIS_URL);
assert !(service.environment ? BUZZ_S3_ENDPOINT);
pkgs.runCommand "buzz-pair-relay-module-eval" { } "touch $out"
