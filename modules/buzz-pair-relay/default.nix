{ config, lib, ... }:
let
  cfg = config.services.buzz-pair-relay;
  bracketHost =
    host: if lib.hasInfix ":" host && !(lib.hasPrefix "[" host) then "[${host}]" else host;
  capabilities = lib.optionalString (cfg.port < 1024) "CAP_NET_BIND_SERVICE";
in
{
  options.services.buzz-pair-relay = {
    enable = lib.mkEnableOption "the standalone Buzz pairing relay";
    package = lib.mkOption {
      type = lib.types.package;
      description = "Package containing bin/buzz-pair-relay. Required when enabled.";
    };
    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Listener address. HTTP path restrictions belong in the reverse proxy, not this service.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "Pairing WebSocket listener port.";
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the listener TCP port in the firewall. This does not change the bind address.";
    };
  };
  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
    systemd.services.buzz-pair-relay = {
      description = "Buzz pairing relay";
      documentation = [ "https://github.com/block/buzz" ];
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment.BUZZ_PAIR_RELAY_BIND_ADDR = "${bracketHost cfg.listenAddress}:${toString cfg.port}";
      serviceConfig = {
        ExecStart = lib.getExe' cfg.package "buzz-pair-relay";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";
        AmbientCapabilities = capabilities;
        CapabilityBoundingSet = capabilities;
        DevicePolicy = "closed";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        ProcSubset = "pid";
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        UMask = "0077";
      };
    };
  };
}
