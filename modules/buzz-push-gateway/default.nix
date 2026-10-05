{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption mkEnableOption types;
  cfg = config.services.buzz-push-gateway;
  # Keep this module usable without importing the relay module. Reserve the
  # enabled relay's ports conservatively, even with distinct bind addresses.
  relay = config.services.buzz-relay or null;
  pairing = config.services.buzz-pair-relay or null;
  pairingPorts = lib.optional (pairing != null && pairing.enable) pairing.port;
  relayPorts =
    if relay != null && relay.enable then
      [
        relay.port
        relay.healthPort
        relay.metricsPort
      ]
      ++ lib.optional relay.redis.createLocally relay.redis.port
    else
      [ ];
  runtimePath = types.addCheck types.str (
    s:
    lib.hasPrefix "/" s
    && !(lib.hasPrefix "/nix/store/" s)
    && !(lib.hasInfix "\n" s)
    && !(lib.hasInfix ":" s)
  );
  secretOption =
    description:
    mkOption {
      type = types.nullOr runtimePath;
      default = null;
      inherit description;
    };
  nonEmpty = types.strMatching ".+";
  socket = host: port: "${if lib.hasInfix ":" host then "[${host}]" else host}:${toString port}";
  secrets = {
    DATABASE_URL = cfg.databaseUrlFile;
    BUZZ_PUSH_GRANT_KEYS = cfg.grantKeysFile;
    BUZZ_PUSH_TOKEN_KEYS = cfg.tokenKeysFile;
    apns-identity = cfg.apns.identityFile;
    app-attest-root = cfg.appAttest.rootCertificateFile;
  };
  load =
    attrs:
    lib.mapAttrsToList (name: path: "${name}:${path}") (lib.filterAttrs (_: path: path != null) attrs);
  hardening = {
    DynamicUser = true;
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    RestrictSUIDSGID = true;
    RestrictRealtime = true;
    LockPersonality = true;
    CapabilityBoundingSet = "";
    AmbientCapabilities = "";
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
    ];
    UMask = "0077";
  };
in
{
  options.services.buzz-push-gateway = {
    enable = mkEnableOption "the standalone Buzz APNs push gateway";
    package = mkOption {
      type = types.package;
      description = "Package providing bin/buzz-push-gateway.";
    };
    listenAddress = mkOption {
      type = nonEmpty;
      default = "127.0.0.1";
      description = "Numeric public listener IP, without IPv6 brackets. Place behind a TLS proxy.";
    };
    port = mkOption {
      type = types.port;
      default = 8090;
      description = "Public HTTP listener port. Must differ from enabled relay, pairing, and local Redis ports.";
    };
    healthAddress = mkOption {
      type = nonEmpty;
      default = "127.0.0.1";
      description = "Numeric private health and metrics listener IP, without IPv6 brackets. Never expose publicly.";
    };
    healthPort = mkOption {
      type = types.port;
      default = 8091;
      description = "Private probe and metrics port; never opened in the firewall by this module. Must differ from enabled relay, pairing, and local Redis ports.";
    };
    openFirewall = mkEnableOption "opening only the public listener port";
    databaseUrlFile = secretOption "Absolute runtime file containing the dedicated PostgreSQL DML-only DATABASE_URL. Not the relay database. Schema must be migrated separately or with migration.enable.";
    grantKeysFile = secretOption "Runtime file with ordered id:base64-32-bytes keyring, current first, comma-separated.";
    tokenKeysFile = secretOption "Runtime file with independent token-custody keyring. IDs and bytes must not overlap grant keys.";
    appAttest = {
      appId = mkOption {
        type = nonEmpty;
        description = "Server-owned TEAMID.bundle-id for the single compiled-in buzz-ios-dogfood profile.";
      };
      rootCertificateFile = secretOption "Runtime path to the exact Apple App Attestation Root CA PEM pinned by upstream. Loaded read-only; this public certificate is not a secret.";
    };
    apns = {
      topic = mkOption {
        type = nonEmpty;
        description = "Server-owned APNs bundle identifier.";
      };
      environment = mkOption {
        type = types.enum [
          "production"
          "sandbox"
        ];
        default = "production";
        description = "APNs transport environment; App Attest remains production.";
      };
      identityFile = secretOption "Runtime path to combined APNs certificate and unencrypted matching private-key PEM (not a token-signing p8 key).";
    };
    maxGrantLifetimeSeconds = mkOption {
      type = types.ints.between 1 31536000;
      default = 2592000;
      description = "Maximum delivery capability lifetime.";
    };
    maxInstallationLifetimeSeconds = mkOption {
      type = types.ints.between 1 31536000;
      default = 7776000;
      description = "Maximum encrypted-token installation lifetime.";
    };
    endpointQuotaWindowSeconds = mkOption {
      type = types.ints.between 1 86400;
      default = 10;
      description = "Endpoint delivery quota window.";
    };
    endpointQuotaMaxDeliveries = mkOption {
      type = types.ints.between 1 10000;
      default = 10;
      description = "Maximum deliveries per endpoint quota window.";
    };
    migration = {
      enable = mkEnableOption "a separate pre-start gateway schema migration service";
      databaseUrlFile = secretOption "Runtime file containing the separate DDL-capable URL for the same dedicated gateway database. Never loaded into the runtime service.";
      runtimeDatabaseRole = mkOption {
        type = types.strMatching "[a-zA-Z_][a-zA-Z0-9_]{0,62}";
        default = "buzz_push_gateway_runtime";
        description = "Existing PostgreSQL LOGIN role to receive runtime DML grants. An ASCII SQL identifier of 1 to 63 characters, matching upstream validation.";
      };
    };
  };
  config = lib.mkIf cfg.enable {
    assertions =
      (lib.mapAttrsToList (name: path: {
        assertion = path != null;
        message = "services.buzz-push-gateway requires runtime credential ${name}.";
      }) secrets)
      ++ [
        {
          assertion = cfg.port != cfg.healthPort;
          message = "buzz-push-gateway public and private health ports must differ.";
        }
        {
          assertion = lib.intersectLists [ cfg.port cfg.healthPort ] (relayPorts ++ pairingPorts) == [ ];
          message = "services.buzz-push-gateway listener ports must differ from enabled buzz-relay, pairing relay, and local Redis ports.";
        }
        {
          assertion = cfg.port >= 1024 && cfg.healthPort >= 1024;
          message = "buzz-push-gateway requires unprivileged listener ports.";
        }
        {
          assertion = !cfg.migration.enable || cfg.migration.databaseUrlFile != null;
          message = "buzz-push-gateway migration requires a separate DDL databaseUrlFile.";
        }
        {
          assertion = !cfg.migration.enable || cfg.migration.databaseUrlFile != cfg.databaseUrlFile;
          message = "buzz-push-gateway runtime and migration credential paths must differ.";
        }
      ];
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
    systemd.services.buzz-push-gateway = {
      description = "Buzz standalone APNs push gateway";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
      ]
      ++ lib.optional cfg.migration.enable "buzz-push-gateway-migrate.service";
      requires = lib.optional cfg.migration.enable "buzz-push-gateway-migrate.service";
      environment = {
        BUZZ_PUSH_BIND_ADDR = socket cfg.listenAddress cfg.port;
        BUZZ_PUSH_HEALTH_ADDR = socket cfg.healthAddress cfg.healthPort;
        BUZZ_PUSH_DOGFOOD_APP_ATTEST_APP_ID = cfg.appAttest.appId;
        BUZZ_PUSH_APP_ATTEST_ENVIRONMENT = "production";
        BUZZ_PUSH_DOGFOOD_APNS_TOPIC = cfg.apns.topic;
        BUZZ_PUSH_DOGFOOD_APNS_ENVIRONMENT = cfg.apns.environment;
        BUZZ_PUSH_MAX_GRANT_LIFETIME_SECONDS = toString cfg.maxGrantLifetimeSeconds;
        BUZZ_PUSH_MAX_INSTALLATION_LIFETIME_SECONDS = toString cfg.maxInstallationLifetimeSeconds;
        BUZZ_PUSH_ENDPOINT_QUOTA_WINDOW_SECONDS = toString cfg.endpointQuotaWindowSeconds;
        BUZZ_PUSH_ENDPOINT_QUOTA_MAX_DELIVERIES = toString cfg.endpointQuotaMaxDeliveries;
      };
      script = ''
        export DATABASE_URL="$(< "$CREDENTIALS_DIRECTORY/DATABASE_URL")"
        export BUZZ_PUSH_GRANT_KEYS="$(< "$CREDENTIALS_DIRECTORY/BUZZ_PUSH_GRANT_KEYS")"
        export BUZZ_PUSH_TOKEN_KEYS="$(< "$CREDENTIALS_DIRECTORY/BUZZ_PUSH_TOKEN_KEYS")"
        export BUZZ_PUSH_DOGFOOD_APNS_CERT_PATH="$CREDENTIALS_DIRECTORY/apns-identity"
        export BUZZ_PUSH_APP_ATTEST_ROOT_CERT_PATH="$CREDENTIALS_DIRECTORY/app-attest-root"
        exec ${lib.getExe' cfg.package "buzz-push-gateway"}
      '';
      serviceConfig = hardening // {
        LoadCredential = load secrets;
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 45;
      };
    };
    systemd.services.buzz-push-gateway-migrate = lib.mkIf cfg.migration.enable {
      description = "Migrate the dedicated Buzz push gateway database";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      before = [ "buzz-push-gateway.service" ];
      environment.BUZZ_PUSH_RUNTIME_DATABASE_ROLE = cfg.migration.runtimeDatabaseRole;
      script = ''
        export DATABASE_URL="$(< "$CREDENTIALS_DIRECTORY/DATABASE_URL")"
        exec ${lib.getExe' cfg.package "buzz-push-gateway"} --migrate-only
      '';
      serviceConfig = hardening // {
        Type = "oneshot";
        LoadCredential = load { DATABASE_URL = cfg.migration.databaseUrlFile; };
      };
    };
  };
}
