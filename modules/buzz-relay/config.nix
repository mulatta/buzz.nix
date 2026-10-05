{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.buzz-relay;

  hasSecret = name: builtins.hasAttr name cfg.secretFiles;

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
  // lib.optionalAttrs cfg.media.useDefaultCredentials {
    BUZZ_S3_ACCESS_KEY = "";
    BUZZ_S3_SECRET_KEY = "";
  }
  // optionalEnv "RELAY_OWNER_PUBKEY" cfg.ownerPubkey
  // optionalEnv "BUZZ_ADMIN_HOST" cfg.adminHost
  // optionalEnv "BUZZ_CORS_ORIGINS" (if cfg.corsOrigins == [ ] then null else csv cfg.corsOrigins)
  // optionalEnv "BUZZ_EPHEMERAL_TTL_OVERRIDE" cfg.ephemeralTtlOverride
  // optionalEnv "BUZZ_PAIRING_RELAY_URL" cfg.pairingRelay.url;

  secretEnvironmentKeys = [
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "AWS_SESSION_TOKEN"
    "BUZZ_GIT_HOOK_HMAC_SECRET"
    "BUZZ_KLIPY_API_KEY"
    "BUZZ_RELAY_PRIVATE_KEY"
    "BUZZ_S3_ACCESS_KEY"
    "BUZZ_S3_SECRET_KEY"
    "DATABASE_URL"
    "READ_DATABASE_URL"
    "REDIS_URL"
  ];

  reservedEnvironmentKeys =
    secretEnvironmentKeys
    ++ [
      "BUZZ_ADMIN_HOST"
      "BUZZ_ADMIN_WEB_DIR"
      "BUZZ_CORS_ORIGINS"
      "BUZZ_EPHEMERAL_TTL_OVERRIDE"
      "BUZZ_PAIRING_RELAY_URL"
      "BUZZ_WEB_DIR"
      "PATH"
      "RELAY_OWNER_PUBKEY"
      "SSL_CERT_FILE"
    ]
    ++ builtins.attrNames generatedEnvironment;

  invalidSecretEnvironmentKeys = lib.subtractLists secretEnvironmentKeys (
    builtins.attrNames cfg.secretFiles
  );

  relayCommand = pkgs.writeShellScript "buzz-relay-start" (
    ''
      set -eu
    ''
    + lib.concatMapStringsSep "\n" (name: ''
      export ${name}="$(${lib.getExe' pkgs.coreutils "cat"} "$CREDENTIALS_DIRECTORY/${name}")"
    '') (builtins.attrNames cfg.secretFiles)
    + ''
      exec ${lib.getExe cfg.package}
    ''
  );

  environmentKeyConflicts = lib.intersectLists reservedEnvironmentKeys (
    builtins.attrNames cfg.environment
  );

  ports = [
    cfg.port
    cfg.healthPort
    cfg.metricsPort
  ]
  ++ lib.optional config.services.buzz-pair-relay.enable config.services.buzz-pair-relay.port
  ++ lib.optional cfg.redis.createLocally cfg.redis.port;

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
    warnings =
      lib.optional (cfg.corsOrigins == [ ] && !cfg.allowPermissiveCors)
        "services.buzz-relay.corsOrigins is empty: upstream enables permissive CORS. Set explicit origins for production or allowPermissiveCors = true to acknowledge this.";

    assertions = [
      {
        assertion = validWebSocketUrl cfg.relayUrl;
        message = "services.buzz-relay.relayUrl must be a ws:// or wss:// URL without credentials or a fragment.";
      }
      {
        assertion = cfg.database.createLocally || hasSecret "DATABASE_URL";
        message = "services.buzz-relay.secretFiles.DATABASE_URL is required unless database.createLocally is enabled.";
      }
      {
        assertion = cfg.redis.createLocally || hasSecret "REDIS_URL";
        message = "services.buzz-relay.secretFiles.REDIS_URL is required unless redis.createLocally is enabled.";
      }
      {
        assertion = hasSecret "BUZZ_RELAY_PRIVATE_KEY";
        message = "services.buzz-relay.secretFiles.BUZZ_RELAY_PRIVATE_KEY is required, even when relay membership is disabled.";
      }
      {
        assertion =
          if cfg.media.useDefaultCredentials then
            !(hasSecret "BUZZ_S3_ACCESS_KEY" || hasSecret "BUZZ_S3_SECRET_KEY")
          else
            hasSecret "BUZZ_S3_ACCESS_KEY" && hasSecret "BUZZ_S3_SECRET_KEY";
        message = "services.buzz-relay requires both BUZZ_S3_ACCESS_KEY and BUZZ_S3_SECRET_KEY in secretFiles, or media.useDefaultCredentials with neither static credential file.";
      }
      {
        assertion = hasSecret "AWS_ACCESS_KEY_ID" == hasSecret "AWS_SECRET_ACCESS_KEY";
        message = "services.buzz-relay.secretFiles must configure AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY together.";
      }
      {
        assertion = invalidSecretEnvironmentKeys == [ ];
        message = "services.buzz-relay.secretFiles contains unsupported environment keys: ${lib.concatStringsSep ", " invalidSecretEnvironmentKeys}";
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
        message = "services.buzz-relay listener ports, including local Redis, must be unique.";
      }
      {
        assertion = cfg.git.repoPath != cfg.git.packCachePath;
        message = "services.buzz-relay Git repository and pack cache paths must differ.";
      }
      {
        assertion = !cfg.pairingRelay.enable || config.services.buzz-pair-relay.enable;
        message = "services.buzz-relay.pairingRelay.enable requires services.buzz-pair-relay.enable.";
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

    networking.firewall.allowedTCPPorts = lib.optionals cfg.openFirewall [ cfg.port ];

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
      wants = [
        "network-online.target"
      ]
      ++ lib.optional cfg.pairingRelay.enable "buzz-pair-relay.service";
      after = [
        "network-online.target"
      ]
      ++ lib.optional cfg.pairingRelay.enable "buzz-pair-relay.service";
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
          ExecStart = relayCommand;
          LoadCredential = lib.mapAttrsToList (name: path: "${name}:${path}") cfg.secretFiles;
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

    services.buzz-pair-relay = lib.mkIf cfg.pairingRelay.enable {
      enable = lib.mkDefault true;
      # Preserve custom relay bundles, including test packages. The standalone
      # flake module provides a lower-priority default when used on its own.
      package = lib.mkDefault cfg.package;
    };
  };
}
