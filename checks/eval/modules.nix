{
  pkgs,
  relayModule,
  pushModule,
}:
let
  inherit (pkgs) lib;
  evaluate =
    extra:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        relayModule
        pushModule
        {
          boot.isContainer = true;
          system.stateVersion = "25.11";
          services.buzz-relay = {
            enable = true;
            relayUrl = "wss://buzz.example";
            ownerPubkey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
            corsOrigins = [ "https://buzz.example" ];
            media = {
              baseUrl = "https://buzz.example/media";
              s3Endpoint = "https://s3.example";
            };
            database.createLocally = true;
            redis.createLocally = true;
            secretFiles = {
              BUZZ_RELAY_PRIVATE_KEY = "/run/secrets/key";
              BUZZ_S3_ACCESS_KEY = "/run/secrets/access";
              BUZZ_S3_SECRET_KEY = "/run/secrets/secret";
            };
          };
          services.buzz-push-gateway = {
            enable = true;
            databaseUrlFile = "/run/secrets/push-db";
            grantKeysFile = "/run/secrets/grants";
            tokenKeysFile = "/run/secrets/tokens";
            appAttest.appId = "TEAM.com.example";
            appAttest.rootCertificateFile = "/run/certs/apple.pem";
            apns.topic = "com.example";
            apns.identityFile = "/run/secrets/apns.pem";
          };
        }
        extra
      ];
    }).config;
  valid = extra: lib.all (a: a.assertion) (evaluate extra).assertions;
in
assert valid { };
assert lib.all (port: !(valid { services.buzz-push-gateway.port = port; })) [
  3000
  8080
  9102
  6380
];
assert lib.all (port: !(valid { services.buzz-push-gateway.healthPort = port; })) [
  3000
  8080
  9102
  6380
];
assert valid { services.buzz-pair-relay.enable = true; };
assert
  !(valid {
    services.buzz-pair-relay = {
      enable = true;
      port = 8090;
    };
  });
assert
  !(valid {
    services.buzz-relay.enable = lib.mkForce false;
    services.buzz-pair-relay = {
      enable = true;
      port = 8091;
    };
  });
pkgs.runCommand "buzz-module-interoperability" { } "touch $out"
