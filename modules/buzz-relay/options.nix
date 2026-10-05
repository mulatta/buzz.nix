{
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    ;

  runtimePath = types.externalPath;
in
{
  options.services.buzz-relay = {
    enable = mkEnableOption "Buzz relay";

    package = lib.mkPackageOption pkgs "buzz-relay" {
      default = null;
      extraDescription = "It must also provide the {command}`buzz-pair-relay` executable when the local pairing relay is enabled.";
    };

    listenAddress = mkOption {
      type = types.nonEmptyStr;
      default = "127.0.0.1";
      description = "IP address on which the application listener binds.";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "TCP port for the application listener.";
    };

    healthPort = mkOption {
      type = types.port;
      default = 8080;
      description = ''
        TCP port for the health listener. Upstream binds this listener to all
        interfaces regardless of [](#opt-services.buzz-relay.listenAddress).
      '';
    };

    metricsPort = mkOption {
      type = types.port;
      default = 9102;
      description = ''
        TCP port for the Prometheus metrics listener. Upstream binds this
        listener to all interfaces regardless of
        [](#opt-services.buzz-relay.listenAddress).
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to open the application listener port in the firewall. Health
        and metrics ports are never opened automatically.
      '';
    };

    relayUrl = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      example = "wss://buzz.example";
      description = "Public WebSocket URL of this relay. Required when the service is enabled.";
    };

    ownerPubkey = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = "Relay owner's 64-character hexadecimal Nostr public key. Required when relay membership is enforced.";
    };

    secretFiles = mkOption {
      type = types.attrsOf runtimePath;
      default = { };
      example = {
        DATABASE_URL = "/run/secrets/buzz-database-url";
        REDIS_URL = "/run/secrets/buzz-redis-url";
        BUZZ_RELAY_PRIVATE_KEY = "/run/secrets/buzz-relay-private-key";
      };
      description = ''
        Runtime credential files keyed by the exact upstream environment
        variable to populate. Supported keys are restricted to known secrets.
        systemd loads each file with {option}`LoadCredential`; files are not
        copied into the Nix store and cannot override typed or package-owned
        environment variables. Each file contains only the raw value, without
        an environment-variable name or shell quoting. BUZZ_RELAY_PRIVATE_KEY
        is always required. DATABASE_URL and REDIS_URL are required unless their
        local service is enabled. Both BUZZ_S3_ACCESS_KEY and BUZZ_S3_SECRET_KEY
        are required unless media.useDefaultCredentials is enabled. Optional
        credentials such as READ_DATABASE_URL and BUZZ_KLIPY_API_KEY are not
        required. AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be paired.
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        BUZZ_RATE_LIMIT_HUMAN_MESSAGES_PER_MIN = "120";
      };
      description = ''
        Additional non-secret environment variables for upstream settings that
        have no typed option. Values are stored in the world-readable Nix store.
        Generated, secret, and package-owned variables are rejected.
      '';
    };

    redisPoolSize = mkOption {
      type = types.ints.positive;
      default = 16;
      description = "Maximum number of connections in the shared Redis pool.";
    };

    databasePoolSize = mkOption {
      type = types.ints.between 1 4294967295;
      default = 50;
      description = "Maximum number of connections in each PostgreSQL writer or read-replica pool.";
    };

    autoMigrate = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether the relay applies database migrations during startup. This
        production-oriented module default differs from upstream, which does
        not migrate unless explicitly enabled.
      '';
    };

    auditEnabled = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to write the tamper-evident event and media audit log. This does
        not disable the separate moderation audit trail.
      '';
    };

    requireAuthToken = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether REST API requests require authentication tokens. This secure
        module default differs from upstream's permissive default.
      '';
    };

    requireRelayMembership = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether clients must belong to this relay's community. This secure
        module default differs from upstream's permissive default.
      '';
    };

    allowNipOaAuth = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to accept NIP-OA authorization. This module enables NIP-OA by
        default, unlike upstream; disable it to require the other configured
        authentication paths.
      '';
    };

    pubkeyAllowlist = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enforce the relay public-key allowlist.";
    };

    adminHost = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      example = "admin.buzz.example";
      description = "Exact HTTP authority, including an optional port, that enables the bundled administration UI.";
    };

    corsOrigins = mkOption {
      type = types.listOf types.nonEmptyStr;
      default = [ ];
      example = [ "https://buzz.example" ];
      description = "Allowed CORS origins. An empty list enables upstream's permissive development mode; set an explicit list for production.";
    };

    allowPermissiveCors = mkOption {
      type = types.bool;
      default = false;
      description = "Acknowledge upstream's permissive CORS mode when corsOrigins is empty and suppress its warning.";
    };

    maxConnections = mkOption {
      type = types.ints.positive;
      default = 10000;
      description = "Maximum number of concurrent client connections.";
    };

    maxConcurrentHandlers = mkOption {
      type = types.ints.positive;
      default = 1024;
      description = "Maximum number of concurrently executing event handlers.";
    };

    sendBuffer = mkOption {
      type = types.ints.positive;
      default = 1000;
      description = "Number of outbound messages buffered per connection.";
    };

    maxFrameBytes = mkOption {
      type = types.ints.positive;
      default = 512 * 1024;
      description = "Maximum inbound WebSocket frame size in bytes.";
    };

    slowClientGraceLimit = mkOption {
      type = types.ints.between 1 255;
      default = 15;
      description = "Number of consecutive full-buffer events tolerated before disconnecting a slow client.";
    };

    ephemeralTtlOverride = mkOption {
      type = types.nullOr (types.ints.between 1 2147483647);
      default = null;
      example = 60;
      description = ''
        Optional lifetime in seconds applied to every ephemeral channel instead
        of its client-provided TTL.
      '';
    };

    huddleAudioAvailable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether NIP-11 advertises huddle audio. Disable this for multi-instance
        deployments without an external SFU.
      '';
    };

    logFilter = mkOption {
      type = types.str;
      default = "buzz_relay=info";
      example = "buzz_relay=debug,tower_http=info";
      description = "Tracing filter passed through {env}`RUST_LOG`.";
    };

    pushGateway.deliveryUrl = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      example = "https://push.buzz.xyz/v1/deliveries/apns";
      description = ''
        APNs push gateway delivery endpoint. Null explicitly disables push
        delivery instead of using upstream's public gateway default.
      '';
    };

    media = {
      useDefaultCredentials = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Use the AWS default credential chain for media and Git storage instead
          of BUZZ_S3_ACCESS_KEY and BUZZ_S3_SECRET_KEY credential files. Explicitly
          clears upstream's development keys. Supports AWS environment credentials
          supplied through secretFiles or an instance/container role. Provider
          files must be readable within the service sandbox.
        '';
      };

      baseUrl = mkOption {
        type = types.nullOr types.nonEmptyStr;
        default = null;
        example = "https://buzz.example/media";
        description = "Public base URL from which clients download media. Required when the service is enabled.";
      };

      s3Endpoint = mkOption {
        type = types.nullOr types.nonEmptyStr;
        default = null;
        example = "https://s3.example";
        description = "Endpoint of the S3-compatible object store. Required when the service is enabled.";
      };

      s3Bucket = mkOption {
        type = types.nonEmptyStr;
        default = "buzz-media";
        description = "S3 bucket used for media and canonical Git objects.";
      };

      s3Region = mkOption {
        type = types.nonEmptyStr;
        default = "us-east-1";
        description = "S3 region used for request signing.";
      };
    };

    git = {
      repoPath = mkOption {
        type = runtimePath;
        default = "/var/lib/buzz-relay/repos";
        description = "Local Git scratch directory, created with mode 0700 and owned by the relay user.";
      };

      packCachePath = mkOption {
        type = runtimePath;
        default = "/var/cache/buzz-relay/git-pack-cache";
        description = "Local Git pack cache directory, created with mode 0700 and owned by the relay user.";
      };

      maxPackBytes = mkOption {
        type = types.ints.positive;
        default = 524288000;
        description = "Maximum accepted Git pack size in bytes.";
      };

      maxRepoBytes = mkOption {
        type = types.ints.positive;
        default = 1048576000;
        description = "Maximum logical Git repository size in bytes.";
      };

      packCacheMaxBytes = mkOption {
        type = types.ints.positive;
        default = 5368709120;
        description = "Maximum local Git pack cache size in bytes.";
      };

      packCacheMaxConcurrentPopulations = mkOption {
        type = types.ints.positive;
        default = 2;
        description = "Maximum number of concurrent pack-cache population jobs.";
      };

      maxReposPerPubkey = mkOption {
        type = types.ints.positive;
        default = 100;
        description = "Maximum number of Git repositories owned by one public key.";
      };

      maxConcurrentOps = mkOption {
        type = types.ints.positive;
        default = 20;
        description = "Maximum number of concurrent Git operations.";
      };
    };

    pairingRelay = {
      enable = mkEnableOption "a local Buzz pairing sidecar via services.buzz-pair-relay";

      url = mkOption {
        type = types.nullOr types.nonEmptyStr;
        default = null;
        example = "wss://buzz.example/pair";
        description = ''
          Public WebSocket URL advertised for pairing. This may point to the
          local pairing service or an externally operated service. It is
          required when the local pairing service is enabled without the nginx
          helper. With the helper, it defaults to /pair on the main public host.
          Process settings belong to services.buzz-pair-relay.
        '';
      };

    };
  };
}
