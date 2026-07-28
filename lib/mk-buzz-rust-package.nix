{
  lib,
  pkgs,
  source,
}:

let
  rustToolchain = pkgs.rust-bin.stable.${source.rustVersion}.default;

  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };

  commonArgs = {
    inherit (source) version src;
    cargoHash = source.rootCargoHash;
    strictDeps = true;
    doCheck = false;

    meta = {
      homepage = "https://github.com/block/buzz";
      license = lib.licenses.asl20;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  };

  agentCommonArgs = commonArgs // {
    nativeBuildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      pkgs.pkg-config
    ];

    buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      pkgs.openssl
    ];
  };
in
{
  inherit
    rustPlatform
    rustToolchain
    commonArgs
    agentCommonArgs
    ;

  mkAgentTool =
    {
      pname,
      package,
      binary,
      metaDescription,
      installCheckPhase ? null,
    }:
    rustPlatform.buildRustPackage (
      agentCommonArgs
      // {
        inherit pname;
        cargoBuildFlags = [
          "-p"
          package
          "--bin"
          binary
        ];
        doInstallCheck = true;
        installCheckPhase =
          if installCheckPhase != null then
            installCheckPhase
          else
            ''
              test -x "$out/bin/${binary}"
            '';
        meta = agentCommonArgs.meta // {
          description = metaDescription;
          mainProgram = binary;
        };
      }
    );
}
