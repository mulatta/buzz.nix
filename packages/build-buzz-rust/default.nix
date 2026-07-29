{
  lib,
  pkgs,
  source,
}:

let
  data = lib.importJSON ./hashes.json;

  rustToolchain = pkgs.rust-bin.stable.${source.rustVersion}.default;

  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };

  commonMeta = {
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
in
{
  pname,
  package ? pname,
  binary ? package,
  targets ? [ { inherit package binary; } ],
  version ? source.version,
  metaDescription,
  mainProgram ? binary,
  needsOpenSSL ? true,
  installCheckPhase ? null,
}:

let
  cargoBuildFlags = lib.concatMap (target: [
    "-p"
    target.package
    "--bin"
    target.binary
  ]) targets;

  buildsRelay = lib.any (target: target.package == "buzz-relay") targets;
in
rustPlatform.buildRustPackage (
  {
    inherit
      cargoBuildFlags
      pname
      version
      ;
    inherit (source) src;
    inherit (data) cargoHash;

    strictDeps = true;
    doCheck = false;

    nativeBuildInputs = lib.optionals (needsOpenSSL && pkgs.stdenv.hostPlatform.isLinux) [
      pkgs.pkg-config
    ];
    buildInputs = lib.optionals (needsOpenSSL && pkgs.stdenv.hostPlatform.isLinux) [ pkgs.openssl ];

    doInstallCheck = true;
    installCheckPhase =
      if installCheckPhase != null then
        installCheckPhase
      else
        ''
          test -x "$out/bin/${binary}"
        '';

    meta =
      commonMeta
      // {
        description = metaDescription;
      }
      // lib.optionalAttrs (mainProgram != null) { inherit mainProgram; };
  }
  // lib.optionalAttrs buildsRelay {
    postPatch = ''
      substituteInPlace crates/buzz-relay/src/api/git/hook.rs \
        --replace-fail '#!/usr/bin/env bash' '#!${lib.getExe pkgs.bashNonInteractive}'
    '';
  }
)
