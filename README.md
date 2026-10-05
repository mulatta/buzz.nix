# buzz.nix

Reproducible Nix packages for [block/buzz](https://github.com/block/buzz).

This flake pins Buzz to the release tag recorded in `packages/source/pin.json` and builds the Rust, web, relay, and desktop artifacts without import-from-derivation.

## Packages

| Package | Description |
| ----------------------- | -------------------------------------------------------------------- |
| `buzz-cli` | Buzz command-line client (`buzz`) |
| `buzz-acp` | ACP harness for Buzz agent integrations |
| `buzz-agent` | Minimal ACP-compliant Buzz agent |
| `sprig` | All-in-one ACP harness, agent, and developer MCP (independently versioned) |
| `buzz-backend-kubernetes` | Kubernetes backend provider for remote agents |
| `buzz-dev-mcp` | MCP server for shell and file-edit tools |
| `git-credential-nostr` | Git credential helper for NIP-98 authentication |
| `git-sign-nostr` | Nostr signing backend for Git commits and tags |
| `buzz-agent-tools` | Convenience bundle for CLI and agent tools |
| `buzz-web` | Web client bundle |
| `buzz-admin-web` | Relay administration UI bundle |
| `buzz-server-binaries` | Server binary bundle (`buzz-relay`, `buzz-admin`, `buzz-pair-relay`) |
| `buzz-relay` | Relay runtime package with bundled web UIs |
| `buzz-push-gateway` | Standalone production APNs push gateway; requires separate database and Apple credentials |
| `buzz-desktop-frontend` | Frontend bundle embedded in Buzz Desktop |
| `buzz-desktop-sidecars` | Sidecar bundle required by Buzz Desktop |
| `buzz-desktop` | Tauri desktop application |

## Usage

Run the CLI:

```sh
nix run github:mulatta/buzz.nix#buzz-cli -- --help
```

The CLI package includes the upstream agent skill at
`share/skills/buzz-cli/sprout-cli/SKILL.md` (its declared skill name is
`buzz-cli`). The `buzz-agent-tools` bundle also exposes it. Only the CLI skill
is packaged; repository-development and example skills are excluded.

Packaging does not register the skill with an agent. Link the installed
`share/skills/buzz-cli/sprout-cli` directory into the desired agent's skill
directory, such as `~/.claude/skills/buzz-cli`. On NixOS, add
`environment.pathsToLink = [ "/share/skills" ];` when exposing skills through
the system profile. Keep credentials in the runtime environment, not in the
skill or Nix configuration.

Run the relay:

```sh
nix run github:mulatta/buzz.nix#buzz-relay
```

`buzz-relay` expects runtime services such as Postgres to be configured. A bare run starts the binary, but database connection failures are expected without a database and `DATABASE_URL`.

Build the desktop package:

```sh
nix build github:mulatta/buzz.nix#buzz-desktop
```

## Standalone pairing relay

The pairing service is independent of the main relay and needs no PostgreSQL,
Redis, or S3. Import `buzz.nixosModules.buzz-pair-relay` to run it on a separate
host:

```nix
{
  imports = [ inputs.buzz.nixosModules.buzz-pair-relay ];
  services.buzz-pair-relay = {
    enable = true;
    # package is supplied by the flake; override with any package providing
    # bin/buzz-pair-relay when needed.
    listenAddress = "127.0.0.1";
    port = 5000;
    openFirewall = false;
  };

  services.nginx = {
    enable = true;
    virtualHosts."pair.example.com" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "= /pair" = {
          proxyPass = "http://127.0.0.1:5000";
          proxyWebsockets = true;
          recommendedProxySettings = true;
          extraConfig = "proxy_read_timeout 130s;";
        };
        "/".return = "404";
      };
    };
  };
  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@example.com";
  };
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

The binary does not restrict request paths. Keep its listener private and expose
only exact `/pair` through a TLS reverse proxy. The flake uses the server-binary
package by default, without pulling in the relay's web UI bundles.

## NixOS module

Expose the relay as a system service:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    buzz = {
      url = "github:mulatta/buzz.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { buzz, nixpkgs, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        buzz.nixosModules.buzz-relay
        {
          services.buzz-relay = {
            enable = true;
            relayUrl = "wss://buzz.example";
            ownerPubkey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
            secretFiles = {
              DATABASE_URL = "/run/secrets/buzz-database-url";
              REDIS_URL = "/run/secrets/buzz-redis-url";
              BUZZ_RELAY_PRIVATE_KEY = "/run/secrets/buzz-relay-private-key";
              BUZZ_S3_ACCESS_KEY = "/run/secrets/buzz-s3-access-key";
              BUZZ_S3_SECRET_KEY = "/run/secrets/buzz-s3-secret-key";
            };
            media.baseUrl = "https://buzz.example/media";
            media.s3Endpoint = "https://s3.example";
            corsOrigins = [ "https://buzz.example" ];
          };
        }
      ];
    };
  };
}
```

Common relay tuning is exposed through typed options rather than raw environment variables:

```nix
services.buzz-relay = {
  redisPoolSize = 32;
  databasePoolSize = 80;
  maxFrameBytes = 1024 * 1024;
  slowClientGraceLimit = 10;
  auditEnabled = true;
  ephemeralTtlOverride = 60;
};
```

Leave `ephemeralTtlOverride` as `null` (the default) to honor client-provided ephemeral-channel lifetimes. Use `environment` only for non-secret upstream settings without a typed option.

`services.buzz-relay` manages the relay and optional pairing process. External
PostgreSQL and Redis remain the default. Opt into local instances and an Nginx
reverse proxy explicitly:

```nix
services.buzz-relay = {
  enable = true;
  ownerPubkey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
  database.createLocally = true;
  redis.createLocally = true;
  nginx = {
    enable = true;
    hostName = "buzz.example";
    enableACME = true;
    forceSSL = true;
  };
  media = {
    s3Endpoint = "https://<account-id>.r2.cloudflarestorage.com";
    s3Bucket = "buzz";
    s3Region = "auto";
  };
  secretFiles = {
    BUZZ_RELAY_PRIVATE_KEY = "/run/secrets/buzz-relay-private-key";
    BUZZ_S3_ACCESS_KEY = "/run/secrets/buzz-s3-access-key";
    BUZZ_S3_SECRET_KEY = "/run/secrets/buzz-s3-secret-key";
  };
};
security.acme = {
  acceptTerms = true;
  defaults.email = "admin@example.com";
};
networking.firewall.allowedTCPPorts = [ 80 443 ];
```

Local database/cache mode cannot be combined with the corresponding
`secretFiles.DATABASE_URL` or `secretFiles.REDIS_URL`. It configures service
ordering and local connections without putting passwords in the Nix store.
PostgreSQL version selection/upgrades and host-wide Redis/Valkey package policy
remain the host's responsibility. S3 storage, bucket provisioning, DNS, backups,
and secret provisioning are never created automatically.

The Nginx integration supplies overridable defaults for `relayUrl`,
`media.baseUrl`, and `corsOrigins`. It proxies WebSocket traffic and media/Git
uploads, but never health or metrics. Leave it disabled for Caddy, an external
ingress, or custom proxy rules. Configure ACME consent/contact and public firewall
ports on the host. `adminHost` is not an access-control boundary: protect any
administration endpoint with your deployment's access policy.

Configure runtime credentials with `secretFiles`, keyed by the upstream environment variable. Each referenced file contains only the raw secret value. Supported keys include `DATABASE_URL`, `REDIS_URL`, `BUZZ_RELAY_PRIVATE_KEY`, `BUZZ_GIT_HOOK_HMAC_SECRET`, `BUZZ_KLIPY_API_KEY`, and S3 credentials. systemd loads them with `LoadCredential`, so their contents stay out of the Nix store and cannot override typed or package-owned settings. Do not put secret values directly in Nix options.

Set `corsOrigins` explicitly in production. An empty list enables upstream's
permissive development mode and emits a warning. Set `allowPermissiveCors = true`
only to acknowledge that choice explicitly.

The relay requires a signing key and database/cache connection configuration.
Static S3 mode requires both `BUZZ_S3_ACCESS_KEY` and `BUZZ_S3_SECRET_KEY` files.
Set `media.useDefaultCredentials = true` instead to use the AWS default credential
chain; do not combine it with the static Buzz S3 credential files. This explicitly
clears upstream's development credential defaults. Any AWS access/secret key files
must be supplied together. Instance/workload credentials still need to be made
available within the service's systemd sandbox.

Health and metrics listeners are bound by upstream to `0.0.0.0:${healthPort}` and `0.0.0.0:${metricsPort}`. `openFirewall` opens only the main app port; restrict health and metrics with firewall/proxy policy.

APNs push is disabled by default in the NixOS module by setting `BUZZ_PUSH_GATEWAY_DELIVERY_URL` to an empty string. Set `services.buzz-relay.pushGateway.deliveryUrl` explicitly to use Block's public gateway or a separately deployed self-host push gateway.

`nixos-buzz-relay-s3-admission-gate` exercises fail-closed startup with a
test-only proxy that deliberately rejects conditional `If-Match` writes while
forwarding ordinary S3 requests to an unmodified RustFS backend. This does not
assume that any particular RustFS release is broken.

`nixos-buzz-relay-rustfs-integration` exercises successful relay startup,
health/readiness, web/admin routing, restart behavior, and dependency recovery
against unmodified `pkgs.rustfs`. The pinned RustFS 1.0.0 already includes the
exclusive-lock waiter-accounting fix; no local RustFS patch is applied. These
are VM test definitions, not a claim that every S3-compatible backend is safe.

### Pairing and administration

For a same-host sidecar, enable pairing alongside the relay's Nginx helper:

```nix
services.buzz-relay = {
  nginx = { enable = true; hostName = "buzz.example.com"; };
  pairingRelay.enable = true;
  # Defaults to wss://buzz.example.com/pair (ws:// when forceSSL is false).
  # pairingRelay.url = "wss://buzz.example.com/pair";
  adminHost = "admin.buzz.example.com"; # optional
};

# Optional process overrides belong to the standalone service.
services.buzz-pair-relay.port = 5000;
```

This enables `services.buzz-pair-relay` and proxies only exact `/pair` to it.
Other paths still reach the main relay. An explicit local URL may use a separate
DNS hostname with exactly `/pair`; that host returns 404 for other paths. The
helper also supports `/pair` on the configured admin host. Hostnames are
case-insensitive. Custom ports, paths, or TLS policy require a hand-written proxy.

To use a pairing service on another host, set only the advertised URL:

```nix
services.buzz-relay.pairingRelay = {
  enable = false;
  url = "wss://pair.example.com/pair";
};
```

This neither starts a local sidecar nor creates a pairing proxy route. An
independently enabled `services.buzz-pair-relay` is likewise not automatically
exposed by the relay helper. Without the helper, a local sidecar needs an explicit
public URL and a separately configured reverse proxy.

`pairingRelay.listenAddress`, `pairingRelay.port`, and `pairingRelay.openFirewall`
are deprecated aliases for the corresponding `services.buzz-pair-relay` options.
The relay bundle remains the sidecar's default package when the convenience
option is used; `services.buzz-pair-relay.package` can override it.

### Independent APNs gateway

Import `buzz.nixosModules.buzz-push-gateway` separately. It does not enable a
relay, provision PostgreSQL, or configure a public proxy:

```nix
services.buzz-push-gateway = {
  enable = true;
  port = 8090;
  healthPort = 8091;
  databaseUrlFile = "/run/secrets/push-runtime-database-url";
  grantKeysFile = "/run/secrets/push-grant-keys";
  tokenKeysFile = "/run/secrets/push-token-keys";
  appAttest = {
    appId = "TEAMID.com.example.buzz";
    rootCertificateFile = "/run/credentials/apple-app-attestation-root.pem";
  };
  apns = {
    topic = "com.example.buzz";
    identityFile = "/run/secrets/push-apns-identity.pem";
    environment = "production";
  };
  # Optional; otherwise provision the schema outside this service.
  migration = {
    enable = true;
    databaseUrlFile = "/run/secrets/push-migration-database-url";
    runtimeDatabaseRole = "buzz_push_gateway_runtime";
  };
};
```

Use a dedicated gateway database, not the relay database. Provision the runtime
LOGIN role before migration. Runtime credentials should have only the upstream
DML grants; the optional migration unit alone receives the separate DDL URL.
The ordered grant and token keyrings use `id:base64-32-bytes` entries separated
by commas; their IDs and key bytes must not overlap.

The pinned gateway supports the compiled-in `buzz-ios-dogfood` profile and
production App Attest. It requires Apple's exact pinned App Attestation Root CA
and a combined APNs certificate/private-key PEM, **not** an APNs token-signing
`.p8` key. APNs sandbox transport does not enable development App Attest.
Your client must match this profile; packaging alone does not make an arbitrary
iOS app compatible. Upstream attestation audiences remain fixed `push.buzz.xyz`
protocol constants, even when the service is hosted under another domain.

The gateway defaults to public port `8090` and health/metrics port `8091`,
separate from the relay defaults. When both modules are enabled, their listener
ports (including local pairing and Redis) must be distinct, even when bound to
different addresses. Local Redis must also use a port distinct from relay listeners.
Migration role names must be ASCII SQL identifiers of at most 63 characters.

Expose the public HTTP port behind an HTTPS proxy and keep the health/metrics
port private. On the relay, opt in with
`pushGateway.deliveryUrl = "https://push.example/v1/deliveries/apns";`.
There is no implicit connection between the two modules. Both secret files and
public runtime certificate files must exist before the gateway starts.

## Development

Enter the development shell:

```sh
nix develop
```

Run focused checks:

```sh
NIX_CONFIG='allow-import-from-derivation = false' nix flake show
nix build .#checks.aarch64-darwin.package-buzz-cli --no-link
nix build .#checks.aarch64-darwin.package-buzz-desktop --no-link
nix build .#checks.x86_64-linux.package-buzz-desktop --no-link
nix build .#checks.x86_64-linux.module-buzz-pair-relay-options --no-link
nix build .#checks.x86_64-linux.module-buzz-pair-relay --no-link
nix build .#checks.x86_64-linux.module-buzz-relay-options --no-link
nix build .#checks.x86_64-linux.module-evaluation --no-link
nix build .#checks.x86_64-linux.module-buzz-relay-local-options --no-link
nix build .#checks.x86_64-linux.module-buzz-relay-nginx-options --no-link
nix build .#checks.x86_64-linux.module-buzz-push-gateway --no-link
nix build .#checks.x86_64-linux.module-buzz-relay --no-link
nix build .#checks.x86_64-linux.module-buzz-relay-local-stack --no-link
nix build .#checks.x86_64-linux.nixos-buzz-relay-s3-admission-gate --no-link
nix build .#checks.x86_64-linux.nixos-buzz-relay-rustfs-integration --no-link
```

Format repository files:

```sh
nix fmt
```

Update the pinned buzz release:

```sh
./packages/source/update.py --tag desktop-v0.5.9
```

Omit `--tag` to use the latest upstream release. The updater also accepts the
legacy `vX.Y.Z` tags used through Buzz 0.5.2.

## Layout

- `checks/default.nix` assembles package and devShell checks and explicitly registers the x86_64-linux evaluation and VM checks.
- `checks/eval` contains module evaluation tests; `checks/vm` contains service and integration VM tests.
- Evaluation tests return check derivations; inspect them through `checks.x86_64-linux.<name>.drvPath` without building a VM.
- `packages/*/package.nix` are public flake package definitions.
- `packages/source` provides the pinned upstream source plus source-derived metadata needed at evaluation time.
- `packages/build-buzz-frontend` and `packages/build-buzz-rust` are package-scoped internal builders with locally owned dependency hashes.

## Licensing

The Nix packaging code in this repository is licensed under the MIT License.

Packaged software keeps its upstream licenses. Buzz server and agent components are Apache-2.0. The desktop package is marked GPL-3.0-or-later because the final desktop binary includes sherpa-onnx/eSpeak NG native code.
