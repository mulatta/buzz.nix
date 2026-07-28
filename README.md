# buzz.nix

Reproducible Nix packages for [block/buzz](https://github.com/block/buzz).

This flake pins Buzz to the release tag recorded in `packages/source/hashes.json` and builds the Rust, web, relay, and desktop artifacts without import-from-derivation.

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
```

Format Nix files:

```sh
nix fmt
```

## Layout

- `packages/*/package.nix` are public flake package definitions.
- `packages/source` and `packages/pnpm-deps` are internal derivations used by the package scope.
- `lib` contains shared package helpers exposed through `lib.buzz`.

## Licensing

The Nix packaging code in this repository is licensed under the MIT License.

Packaged software keeps its upstream licenses. Buzz server and agent components are Apache-2.0. The desktop package is marked GPL-3.0-or-later because the final desktop binary includes sherpa-onnx/eSpeak NG native code.
