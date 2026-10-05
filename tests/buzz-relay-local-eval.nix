# Run with: nix-instantiate --eval --strict --json tests/buzz-relay-local-eval.nix --arg nixpkgs /path/to/nixpkgs
{ nixpkgs }:
let
  lib = import (nixpkgs + "/lib");
  evaluate =
    extra:
    (import (nixpkgs + "/nixos/lib/eval-config.nix") {
      system = "x86_64-linux";
      modules = [
        ../modules/buzz-pair-relay
        ../modules/buzz-relay/options.nix
        ../modules/buzz-relay/config.nix
        ../modules/buzz-relay/local-services.nix
        ({ pkgs, ... }: {
          services.buzz-relay = {
            enable = true;
            package = pkgs.hello;
            relayUrl = "wss://buzz.example";
            requireRelayMembership = false;
            media.baseUrl = "https://buzz.example/media";
            media.s3Endpoint = "http://127.0.0.1:9000";
            secretFiles.BUZZ_RELAY_PRIVATE_KEY = "/run/secrets/relay-key";
          };
          system.stateVersion = "25.11";
        })
        extra
      ];
    }).config;
  local = evaluate {
    services.buzz-relay.database.createLocally = true;
    services.buzz-relay.redis.createLocally = true;
  };
  remote = evaluate { };
  conflict = evaluate {
    services.buzz-relay.database.createLocally = true;
    services.buzz-relay.redis.createLocally = true;
    services.buzz-relay.secretFiles = {
      DATABASE_URL = "/run/secrets/db";
      REDIS_URL = "/run/secrets/redis";
    };
  };
  disabled = evaluate {
    services.buzz-relay.enable = lib.mkForce false;
    services.buzz-relay.database.createLocally = true;
    services.buzz-relay.redis.createLocally = true;
  };
  failures = c: map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
  conflictMessages = failures conflict;
in
assert local.services.postgresql.enable;
assert local.services.postgresql.ensureDatabases == [ "buzz-relay" ];
assert lib.any (
  u: u.name == "buzz-relay" && u.ensureDBOwnership
) local.services.postgresql.ensureUsers;
assert lib.hasInfix ''local "buzz-relay" "buzz-relay" peer''
  local.services.postgresql.authentication;
assert
  local.systemd.services.buzz-relay.environment.DATABASE_URL
  == "postgresql:///buzz-relay?host=/run/postgresql&user=buzz-relay&port=5432";
assert local.systemd.services.buzz-relay.environment.REDIS_URL == "redis://127.0.0.1:6380";
assert local.services.redis.servers.buzz-relay.bind == "127.0.0.1";
assert !local.services.redis.servers.buzz-relay.openFirewall;
assert lib.all
  (
    unit:
    builtins.elem unit local.systemd.services.buzz-relay.requires
    && builtins.elem unit local.systemd.services.buzz-relay.after
  )
  [
    "postgresql.service"
    "postgresql-setup.service"
    "redis-buzz-relay.service"
  ];
assert !(remote.systemd.services.buzz-relay.environment ? DATABASE_URL);
assert !(remote.systemd.services.buzz-relay.environment ? REDIS_URL);
assert !remote.services.postgresql.enable;
assert remote.services.redis.servers == { };
assert !disabled.services.postgresql.enable;
assert disabled.services.redis.servers == { };
assert builtins.elem
  "services.buzz-relay.database.createLocally conflicts with secretFiles.DATABASE_URL."
  conflictMessages;
assert builtins.elem "services.buzz-relay.redis.createLocally conflicts with secretFiles.REDIS_URL."
  conflictMessages;
{
  success = true;
}
