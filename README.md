# buzz.nix

Reproducible Nix packages for [block/buzz](https://github.com/block/buzz).

This flake pins Buzz to the release tag recorded in `packages/source/pin.json` and builds the Rust, web, relay, and desktop artifacts without import-from-derivation.

## Packages

| Package | Description |
| ----------------------- | -------------------------------------------------------------------- |
| `buzz-cli` | Buzz command-line client (`buzz`) |
| `buzz-acp` | ACP harness for Buzz agent integrations |
| `buzz-agent` | Minimal ACP-compliant Buzz agent |
| `buzz-dev-mcp` | MCP server for shell and file-edit tools |
| `git-credential-nostr` | Git credential helper for NIP-98 authentication |
| `buzz-agent-tools` | Convenience bundle for CLI and agent tools |
| `buzz-web` | Web client bundle |
| `buzz-admin-web` | Relay administration UI bundle |
| `buzz-server-binaries` | Server binary bundle (`buzz-relay`, `buzz-admin`, `buzz-pair-relay`) |
| `buzz-relay` | Relay runtime package with bundled web UIs |
| `buzz-desktop-frontend` | Frontend bundle embedded in Buzz Desktop |
| `buzz-desktop-sidecars` | Sidecar bundle required by Buzz Desktop |
| `buzz-desktop` | Tauri desktop application |

## Usage

Run the CLI:

```sh
nix run github:mulatta/buzz.nix#buzz-cli -- --help
```

Run the relay:

```sh
nix run github:mulatta/buzz.nix#buzz-relay
```

`buzz-relay` expects runtime services such as Postgres to be configured. A bare run starts the binary, but database connection failures are expected without a database and `DATABASE_URL`.

Build the desktop package:

```sh
nix build github:mulatta/buzz.nix#buzz-desktop
```

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
            environmentFiles = [ "/run/secrets/buzz-relay.env" ];
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

`services.buzz-relay` manages the Buzz relay process and optional pairing relay only. PostgreSQL, Redis, S3-compatible storage, bucket setup, reverse proxy, TLS, DNS, and secrets remain host responsibilities.

Secret files must provide runtime credentials such as `DATABASE_URL`, `REDIS_URL`, `BUZZ_RELAY_PRIVATE_KEY`, `BUZZ_GIT_HOOK_HMAC_SECRET`, and S3 credentials when static keys are used. Do not put secrets in Nix options. Keep environment files secret-only: systemd loads them after generated variables, so they must not override typed options or package-owned `PATH`, `SSL_CERT_FILE`, `BUZZ_WEB_DIR`, and `BUZZ_ADMIN_WEB_DIR` values.

Set `corsOrigins` explicitly in production. An empty list enables upstream's permissive development mode.

Health and metrics listeners are bound by upstream to `0.0.0.0:${healthPort}` and `0.0.0.0:${metricsPort}`. `openFirewall` opens only the main app port; restrict health and metrics with firewall/proxy policy.

APNs push is disabled by default in the NixOS module by setting `BUZZ_PUSH_GATEWAY_DELIVERY_URL` to an empty string. Set `services.buzz-relay.pushGateway.deliveryUrl` explicitly to use Block's public gateway or a separately deployed self-host push gateway.

The RustFS release currently packaged by nixpkgs passes basic S3 round trips but returns HTTP 503 during Buzz's concurrent `If-Match` A3 probe. `nixos-buzz-relay-rustfs-gate` verifies that the relay fails closed before opening listeners; it is not a successful integration test or a production endorsement of RustFS.

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
nix build .#checks.x86_64-linux.module-buzz-relay --no-link
nix build .#checks.x86_64-linux.nixos-buzz-relay-rustfs-gate --no-link
```

Format repository files:

```sh
nix fmt
```

Update the pinned buzz release:

```sh
./packages/source/update.py --tag v0.5.0
```

Omit `--tag` to use the latest upstream release.

## Layout

- `packages/*/package.nix` are public flake package definitions.
- `packages/source` provides the pinned upstream source plus source-derived metadata needed at evaluation time.
- `packages/build-buzz-frontend` and `packages/build-buzz-rust` are package-scoped internal builders with locally owned dependency hashes.

## Licensing

The Nix packaging code in this repository is licensed under the MIT License.

Packaged software keeps its upstream licenses. Buzz server and agent components are Apache-2.0. The desktop package is marked GPL-3.0-or-later because the final desktop binary includes sherpa-onnx/eSpeak NG native code.
