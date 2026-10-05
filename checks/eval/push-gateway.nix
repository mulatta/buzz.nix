{ module, pkgs }:
let
  inherit (pkgs) lib;
  evaluate =
    settings:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        module
        (_: {
          boot.isContainer = true;
          system.stateVersion = "25.11";
          services.buzz-push-gateway = {
            enable = true;
            package = pkgs.hello;
            databaseUrlFile = "/run/secrets/gateway-db";
            grantKeysFile = "/run/secrets/grants";
            tokenKeysFile = "/run/secrets/tokens";
            appAttest.appId = "TEAM.xyz.example";
            appAttest.rootCertificateFile = "/run/certs/apple.pem";
            apns.topic = "xyz.example";
            apns.identityFile = "/run/secrets/apns.pem";
          }
          // settings;
        })
      ];
    }).config;
  base = evaluate { };
  migrated = evaluate {
    openFirewall = true;
    migration.enable = true;
    migration.databaseUrlFile = "/run/secrets/gateway-ddl";
  };
  invalid = evaluate { databaseUrlFile = null; };
  role = n: lib.concatStrings (lib.replicate n "a");
  roleValue =
    value:
    (evaluate { migration.runtimeDatabaseRole = value; })
    .services.buzz-push-gateway.migration.runtimeDatabaseRole;
  service = base.systemd.services.buzz-push-gateway;
  ddl = migrated.systemd.services.buzz-push-gateway-migrate;
in
assert lib.all (x: x.assertion) base.assertions;
assert roleValue "a" == "a";
assert roleValue (role 63) == role 63;
assert !(builtins.tryEval (roleValue (role 64))).success;
assert !(builtins.tryEval (roleValue "")).success;
assert !(builtins.tryEval (roleValue "9invalid")).success;
assert lib.all (x: x.assertion) migrated.assertions;
assert !(lib.all (x: x.assertion) invalid.assertions);
assert service.environment.BUZZ_PUSH_BIND_ADDR == "127.0.0.1:8090";
assert service.environment.BUZZ_PUSH_HEALTH_ADDR == "127.0.0.1:8091";
assert service.serviceConfig.DynamicUser;
assert service.serviceConfig.ProtectSystem == "strict";
assert builtins.length service.serviceConfig.LoadCredential == 5;
assert !(service.environment ? DATABASE_URL);
assert !(service.environment ? BUZZ_PUSH_GRANT_KEYS);
assert !(builtins.elem 8091 migrated.networking.firewall.allowedTCPPorts);
assert builtins.elem 8090 migrated.networking.firewall.allowedTCPPorts;
assert ddl.serviceConfig.LoadCredential == [ "DATABASE_URL:/run/secrets/gateway-ddl" ];
assert builtins.elem "buzz-push-gateway-migrate.service"
  migrated.systemd.services.buzz-push-gateway.requires;
pkgs.runCommand "buzz-push-gateway-module-eval" { } "touch $out"
