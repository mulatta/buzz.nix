{
  lib,
  pkgs,
  pnpmDeps,
  source,
}:

let
  pnpm = pkgs.pnpm_11.override {
    nodejs-slim = pkgs.nodejs_24;
  };
in
{
  pname,
  workspace,
  sourceDir,
  metaDescription,
}:

pkgs.stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version src;
  strictDeps = true;

  inherit pnpmDeps;
  pnpmWorkspaces = [ workspace ];

  nativeBuildInputs = [
    pkgs.nodejs_24
    pnpm
    pkgs.pnpmConfigHook
  ];

  buildPhase = ''
    runHook preBuild

    pnpm --filter ${workspace} build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -R ${sourceDir}/dist/. "$out/"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -f "$out/index.html"
  '';

  meta = {
    description = metaDescription;
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
