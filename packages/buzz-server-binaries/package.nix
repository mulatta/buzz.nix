{
  lib,
  pkgs,
  source,
}:

let
  buzzRust = lib.buzz.mkBuzzRustPackage { inherit lib pkgs source; };
in
buzzRust.rustPlatform.buildRustPackage (
  buzzRust.commonArgs
  // {
    pname = "buzz-server-binaries";
    version = source.relayVersion;
    cargoBuildFlags = [
      "-p"
      "buzz-relay"
      "--bin"
      "buzz-relay"
      "-p"
      "buzz-admin"
      "--bin"
      "buzz-admin"
      "-p"
      "buzz-pair-relay"
      "--bin"
      "buzz-pair-relay"
    ];

    postPatch = ''
      substituteInPlace crates/buzz-relay/src/api/git/hook.rs \
        --replace-fail '#!/usr/bin/env bash' '#!${lib.getExe pkgs.bashNonInteractive}'
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      test -x "$out/bin/buzz-relay"
      "$out/bin/buzz-admin" --help >/dev/null
      test -x "$out/bin/buzz-pair-relay"
    '';

    meta = buzzRust.commonArgs.meta // {
      description = "Buzz relay server and administration tools";
    };
  }
)
