{ config, lib, ... }:

let
  cfg = config.services.buzz-relay;
  databaseUnits = [
    "postgresql.service"
    "postgresql-setup.service"
  ];
  redisUnits = [ "redis-buzz-relay.service" ];
in
{
  options.services.buzz-relay = {
    database.createLocally = lib.mkEnableOption "a local PostgreSQL database for Buzz relay" // {
      description = ''
        Create the PostgreSQL database and role named `buzz-relay`. Connect over
        `/run/postgresql` using peer authentication as the relay system user.
        This cannot be combined with `secretFiles.DATABASE_URL`.
      '';
    };

    redis = {
      createLocally = lib.mkEnableOption "a dedicated local Redis instance for Buzz relay";
      port = lib.mkOption {
        type = lib.types.ints.between 1 65535;
        default = 6380;
        description = "Loopback TCP port of the dedicated local Redis instance.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = !cfg.database.createLocally || !(cfg.secretFiles ? DATABASE_URL);
            message = "services.buzz-relay.database.createLocally conflicts with secretFiles.DATABASE_URL.";
          }
          {
            assertion = !cfg.redis.createLocally || !(cfg.secretFiles ? REDIS_URL);
            message = "services.buzz-relay.redis.createLocally conflicts with secretFiles.REDIS_URL.";
          }
        ];
      }
      (lib.mkIf cfg.database.createLocally {
        services.postgresql = {
          enable = true;
          ensureDatabases = [ "buzz-relay" ];
          ensureUsers = [
            {
              name = "buzz-relay";
              ensureDBOwnership = true;
            }
          ];
          # A dedicated peer rule also works when the host replaces the default HBA.
          authentication = lib.mkBefore ''
            local "buzz-relay" "buzz-relay" peer
          '';
        };

        systemd.services.buzz-relay = {
          requires = databaseUnits;
          after = databaseUnits;
          # SQLx accepts a socket directory in the host query parameter. The user
          # and database match the system user for PostgreSQL peer authentication.
          environment.DATABASE_URL = "postgresql:///buzz-relay?host=/run/postgresql&user=buzz-relay&port=${toString config.services.postgresql.settings.port}";
        };
      })
      (lib.mkIf cfg.redis.createLocally {
        services.redis.servers.buzz-relay = {
          enable = true;
          bind = "127.0.0.1";
          port = cfg.redis.port;
          openFirewall = false;
        };

        systemd.services.buzz-relay = {
          requires = redisUnits;
          after = redisUnits;
          environment.REDIS_URL = "redis://127.0.0.1:${toString cfg.redis.port}";
        };
      })
    ]
  );
}
