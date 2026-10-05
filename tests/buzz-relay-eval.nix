{
  pkgs,
  relayModule,
}:
let
  inherit (pkgs) lib;
  eval =
    extra:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        relayModule
        (_: {
          boot.isContainer = true;
          system.stateVersion = "25.11";
        })
        extra
      ];
    }).config;
  base = {
    services.buzz-relay = {
      enable = true;
      ownerPubkey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
      relayUrl = "wss://buzz.example";
      corsOrigins = [ "https://buzz.example" ];
      media = {
        baseUrl = "https://buzz.example/media";
        s3Endpoint = "https://s3.example";
      };
      secretFiles = {
        DATABASE_URL = "/run/secrets/db";
        REDIS_URL = "/run/secrets/redis";
        BUZZ_RELAY_PRIVATE_KEY = "/run/secrets/key";
        BUZZ_S3_ACCESS_KEY = "/run/secrets/s3-access";
        BUZZ_S3_SECRET_KEY = "/run/secrets/s3-secret";
      };
    };
  };
  redisCollision =
    port:
    eval (
      lib.recursiveUpdate base {
        services.buzz-relay = {
          redis = {
            createLocally = true;
            inherit port;
          };
          secretFiles = lib.mkForce (
            builtins.removeAttrs base.services.buzz-relay.secretFiles [ "REDIS_URL" ]
          );
        };
      }
    );
  valid = cfg: lib.all (a: a.assertion) cfg.assertions;
  external = eval base;
  disabled = eval { };
  conflict = eval (
    lib.recursiveUpdate base {
      services.buzz-relay.database.createLocally = true;
    }
  );
  missing =
    key:
    eval (
      base
      // {
        services.buzz-relay = base.services.buzz-relay // {
          secretFiles = builtins.removeAttrs base.services.buzz-relay.secretFiles [ key ];
        };
      }
    );
  local = eval (
    base
    // {
      services.buzz-relay = base.services.buzz-relay // {
        database.createLocally = true;
        redis.createLocally = true;
        nginx = {
          enable = true;
          hostName = "buzz.example";
          enableACME = false;
          forceSSL = false;
        };
        secretFiles = builtins.removeAttrs base.services.buzz-relay.secretFiles [
          "DATABASE_URL"
          "REDIS_URL"
        ];
      };
    }
  );
  sidecar = eval (
    lib.recursiveUpdate base {
      services.buzz-relay = {
        pairingRelay.enable = true;
        nginx = {
          enable = true;
          hostName = "buzz.example";
          enableACME = false;
          forceSSL = false;
        };
      };
    }
  );
  legacySidecar = eval (
    lib.recursiveUpdate base {
      services.buzz-relay.pairingRelay = {
        enable = true;
        url = "wss://pair.example/pair";
        port = 5100;
        openFirewall = true;
      };
    }
  );
  defaultChain = eval (
    base
    // {
      services.buzz-relay = base.services.buzz-relay // {
        media = base.services.buzz-relay.media // {
          useDefaultCredentials = true;
        };
        secretFiles = builtins.removeAttrs base.services.buzz-relay.secretFiles [
          "BUZZ_S3_ACCESS_KEY"
          "BUZZ_S3_SECRET_KEY"
        ];
      };
    }
  );
  permissive = eval (lib.recursiveUpdate base { services.buzz-relay.corsOrigins = [ ]; });
  corsOptIn = eval (
    lib.recursiveUpdate base {
      services.buzz-relay = {
        corsOrigins = [ ];
        allowPermissiveCors = true;
      };
    }
  );
  reserved = eval (
    lib.recursiveUpdate base {
      services.buzz-relay.environment.DATABASE_URL = "must-not-be-in-store";
    }
  );
in
assert valid disabled;
assert valid external;
assert valid (redisCollision 6380);
assert !(valid (redisCollision 3000));
assert !(valid (redisCollision 8080));
assert !(valid (redisCollision 9102));
assert valid local;
assert valid sidecar;
assert sidecar.services.buzz-pair-relay.enable;
assert sidecar.services.buzz-relay.pairingRelay.url == "ws://buzz.example/pair";
assert builtins.elem "buzz-pair-relay.service" sidecar.systemd.services.buzz-relay.wants;
assert valid legacySidecar;
assert legacySidecar.services.buzz-pair-relay.port == 5100;
assert builtins.elem 5100 legacySidecar.networking.firewall.allowedTCPPorts;
assert valid defaultChain;
assert defaultChain.systemd.services.buzz-relay.environment.BUZZ_S3_ACCESS_KEY == "";
assert lib.all (key: !(valid (missing key))) [
  "DATABASE_URL"
  "REDIS_URL"
  "BUZZ_RELAY_PRIVATE_KEY"
  "BUZZ_S3_ACCESS_KEY"
  "BUZZ_S3_SECRET_KEY"
];
assert lib.any (warning: lib.hasInfix "corsOrigins" warning) permissive.warnings;
assert !(lib.any (warning: lib.hasInfix "corsOrigins" warning) corsOptIn.warnings);
assert !(valid conflict);
assert !(valid reserved);
assert !(disabled.systemd.services ? buzz-relay);
assert external.systemd.services.buzz-relay.serviceConfig.ProtectSystem == "strict";
assert external.services.buzz-relay.pushGateway.deliveryUrl == null;
pkgs.runCommand "buzz-relay-evaluation" { } "touch $out"
