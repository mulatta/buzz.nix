{
  config,
  lib,
  ...
}:

let
  cfg = config.services.buzz-relay;

  bool = value: if value then "true" else "false";
  csv = lib.concatStringsSep ",";
  optionalEnv = name: value: lib.optionalAttrs (value != null) { ${name} = toString value; };
  bracketHost =
    host: if lib.hasInfix ":" host && !(lib.hasPrefix "[" host) then "[${host}]" else host;

  generatedEnvironment = {
    BUZZ_BIND_ADDR = "${bracketHost cfg.listenAddress}:${toString cfg.port}";
    BUZZ_HEALTH_PORT = toString cfg.healthPort;
    BUZZ_METRICS_PORT = toString cfg.metricsPort;
    BUZZ_REDIS_POOL_SIZE = toString cfg.redisPoolSize;
    BUZZ_DB_POOL_SIZE = toString cfg.databasePoolSize;
    RELAY_URL = if cfg.relayUrl == null then "" else cfg.relayUrl;
    BUZZ_AUTO_MIGRATE = bool cfg.autoMigrate;
    BUZZ_AUDIT_ENABLED = bool cfg.auditEnabled;
    BUZZ_REQUIRE_AUTH_TOKEN = bool cfg.requireAuthToken;
    BUZZ_REQUIRE_RELAY_MEMBERSHIP = bool cfg.requireRelayMembership;
    BUZZ_REQUIRE_MEDIA_GET_AUTH = bool cfg.requireMediaGetAuth;
    BUZZ_ALLOW_NIP_OA_AUTH = bool cfg.allowNipOaAuth;
    BUZZ_PUBKEY_ALLOWLIST = bool cfg.pubkeyAllowlist;
    BUZZ_MAX_CONNECTIONS = toString cfg.maxConnections;
    BUZZ_MAX_CONCURRENT_HANDLERS = toString cfg.maxConcurrentHandlers;
    BUZZ_SEND_BUFFER = toString cfg.sendBuffer;
    BUZZ_MAX_FRAME_BYTES = toString cfg.maxFrameBytes;
    BUZZ_SLOW_CLIENT_GRACE_LIMIT = toString cfg.slowClientGraceLimit;
    BUZZ_HUDDLE_AUDIO_AVAILABLE = bool cfg.huddleAudioAvailable;
    BUZZ_PUSH_GATEWAY_DELIVERY_URL =
      if cfg.pushGateway.deliveryUrl == null then "" else cfg.pushGateway.deliveryUrl;
    BUZZ_MEDIA_BASE_URL = if cfg.media.baseUrl == null then "" else cfg.media.baseUrl;
    BUZZ_S3_ENDPOINT = if cfg.media.s3Endpoint == null then "" else cfg.media.s3Endpoint;
    BUZZ_S3_BUCKET = cfg.media.s3Bucket;
    BUZZ_S3_REGION = cfg.media.s3Region;
    BUZZ_GIT_REPO_PATH = cfg.git.repoPath;
    BUZZ_GIT_PACK_CACHE_PATH = cfg.git.packCachePath;
    BUZZ_GIT_MAX_PACK_BYTES = toString cfg.git.maxPackBytes;
    BUZZ_GIT_MAX_REPO_BYTES = toString cfg.git.maxRepoBytes;
    BUZZ_GIT_PACK_CACHE_MAX_BYTES = toString cfg.git.packCacheMaxBytes;
    BUZZ_GIT_PACK_CACHE_MAX_CONCURRENT_POPULATIONS = toString cfg.git.packCacheMaxConcurrentPopulations;
    BUZZ_GIT_MAX_REPOS_PER_PUBKEY = toString cfg.git.maxReposPerPubkey;
    BUZZ_GIT_MAX_CONCURRENT_OPS = toString cfg.git.maxConcurrentOps;
    RUST_LOG = cfg.logFilter;
  }
  // optionalEnv "RELAY_OWNER_PUBKEY" cfg.ownerPubkey
  // optionalEnv "BUZZ_ADMIN_HOST" cfg.adminHost
  // optionalEnv "BUZZ_CORS_ORIGINS" (if cfg.corsOrigins == [ ] then null else csv cfg.corsOrigins)
  // optionalEnv "BUZZ_EPHEMERAL_TTL_OVERRIDE" cfg.ephemeralTtlOverride
  // optionalEnv "BUZZ_PAIRING_RELAY_URL" cfg.pairingRelay.url;

  reservedEnvironmentKeys = [
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "AWS_SESSION_TOKEN"
    "BUZZ_ADMIN_HOST"
    "BUZZ_ADMIN_WEB_DIR"
    "BUZZ_CORS_ORIGINS"
    "BUZZ_EPHEMERAL_TTL_OVERRIDE"
    "BUZZ_GIT_HOOK_HMAC_SECRET"
    "BUZZ_PAIRING_RELAY_URL"
    "BUZZ_RELAY_PRIVATE_KEY"
    "BUZZ_S3_ACCESS_KEY"
    "BUZZ_S3_SECRET_KEY"
    "BUZZ_WEB_DIR"
    "DATABASE_URL"
    "PATH"
    "READ_DATABASE_URL"
    "REDIS_URL"
    "RELAY_OWNER_PUBKEY"
    "SSL_CERT_FILE"
  ]
  ++ builtins.attrNames generatedEnvironment;

  environmentKeyConflicts = lib.intersectLists reservedEnvironmentKeys (
    builtins.attrNames cfg.environment
  );

  ports = [
    cfg.port
    cfg.healthPort
    cfg.metricsPort
  ]
  ++ lib.optional cfg.pairingRelay.enable cfg.pairingRelay.port;

  validWebSocketUrl =
    value:
    value != null && builtins.match "wss?://[^/@?#[:space:]]+([/?][^#[:space:]]*)?" value != null;
  validHttpUrl =
    value:
    value != null && builtins.match "https?://[^/@?#[:space:]]+(/[^?#[:space:]]*)?" value != null;
  validPushGatewayUrl =
    value: value == null || builtins.match "https://[^/@?#[:space:]]+/v1/deliveries/apns" value != null;
  validAdminHost =
    value:
    value == null
    || (
      builtins.match "[^[:space:]]+" value != null
      && lib.all (character: !lib.hasInfix character value) [
        "/"
        "\\"
        "@"
      ]
    );

  hardening =
    servicePorts:
    let
      capabilities = lib.optionalString (lib.any (port: port < 1024) servicePorts) "CAP_NET_BIND_SERVICE";
    in
    {
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
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = validWebSocketUrl cfg.relayUrl;
        message = "services.buzz-relay.relayUrl must be a ws:// or wss:// URL without credentials or a fragment.";
      }
      {
        assertion = cfg.environmentFiles != [ ];
        message = "services.buzz-relay.environmentFiles must include at least one secret file.";
      }
      {
        assertion = !cfg.requireRelayMembership || cfg.ownerPubkey != null;
        message = "services.buzz-relay.ownerPubkey is required when requireRelayMembership is true.";
      }
      {
        assertion = cfg.ownerPubkey == null || builtins.match "[0-9a-fA-F]{64}" cfg.ownerPubkey != null;
        message = "services.buzz-relay.ownerPubkey must be 64 hexadecimal characters.";
      }
      {
        assertion = validHttpUrl cfg.media.baseUrl;
        message = "services.buzz-relay.media.baseUrl must be an http:// or https:// URL without credentials, query, or fragment.";
      }
      {
        assertion = validHttpUrl cfg.media.s3Endpoint;
        message = "services.buzz-relay.media.s3Endpoint must be an http:// or https:// URL without credentials, query, or fragment.";
      }
      {
        assertion = validAdminHost cfg.adminHost;
        message = "services.buzz-relay.adminHost must be an exact authority without whitespace, '/', '\\', or '@'.";
      }
      {
        assertion = environmentKeyConflicts == [ ];
        message = "services.buzz-relay.environment must not override generated, secret, or package-owned keys: ${lib.concatStringsSep ", " environmentKeyConflicts}";
      }
      {
        assertion = lib.length ports == lib.length (lib.unique ports);
        message = "services.buzz-relay listener ports must be unique.";
      }
      {
        assertion = cfg.git.repoPath != cfg.git.packCachePath;
        message = "services.buzz-relay Git repository and pack cache paths must differ.";
      }
      {
        assertion = !cfg.pairingRelay.enable || cfg.pairingRelay.url != null;
        message = "services.buzz-relay.pairingRelay.url is required when the local pairing relay is enabled.";
      }
      {
        assertion = cfg.pairingRelay.url == null || validWebSocketUrl cfg.pairingRelay.url;
        message = "services.buzz-relay.pairingRelay.url must be a ws:// or wss:// URL without credentials or a fragment.";
      }
      {
        assertion = validPushGatewayUrl cfg.pushGateway.deliveryUrl;
        message = "services.buzz-relay.pushGateway.deliveryUrl must be an exact HTTPS /v1/deliveries/apns URL without credentials, query, or fragment.";
      }
    ];

    networking.firewall.allowedTCPPorts =
      lib.optionals cfg.openFirewall [ cfg.port ]
      ++ lib.optionals (cfg.pairingRelay.enable && cfg.pairingRelay.openFirewall) [
        cfg.pairingRelay.port
      ];

    users.users.buzz-relay = {
      description = "Buzz relay service user";
      isSystemUser = true;
      group = "buzz-relay";
      home = "/var/lib/buzz-relay";
    };
    users.groups.buzz-relay = { };

    systemd.tmpfiles.settings."10-buzz-relay" =
      lib.genAttrs
        [
          cfg.git.repoPath
          cfg.git.packCachePath
        ]
        (_path: {
          d = {
            mode = "0700";
            user = "buzz-relay";
            group = "buzz-relay";
          };
        });

    systemd.services.buzz-relay = {
      description = "Buzz relay";
      documentation = [ "https://github.com/block/buzz" ];
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = [
        cfg.git.repoPath
        cfg.git.packCachePath
      ];
      environment = generatedEnvironment // cfg.environment;
      serviceConfig =
        hardening [
          cfg.port
          cfg.healthPort
          cfg.metricsPort
        ]
        // {
          ExecStart = lib.getExe cfg.package;
          EnvironmentFile = cfg.environmentFiles;
          User = "buzz-relay";
          Group = "buzz-relay";
          WorkingDirectory = "/var/lib/buzz-relay";
          StateDirectory = "buzz-relay";
          StateDirectoryMode = "0700";
          CacheDirectory = "buzz-relay";
          CacheDirectoryMode = "0700";
          ReadWritePaths = [
            cfg.git.repoPath
            cfg.git.packCachePath
          ];
          Restart = "on-failure";
          RestartSec = "5s";
          TimeoutStopSec = "60s";
        };
    };

    systemd.services.buzz-pair-relay = lib.mkIf cfg.pairingRelay.enable {
      description = "Buzz pairing relay";
      documentation = [ "https://github.com/block/buzz" ];
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment.BUZZ_PAIR_RELAY_BIND_ADDR = "${bracketHost cfg.pairingRelay.listenAddress}:${toString cfg.pairingRelay.port}";
      serviceConfig = hardening [ cfg.pairingRelay.port ] // {
        ExecStart = lib.getExe' cfg.package "buzz-pair-relay";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
