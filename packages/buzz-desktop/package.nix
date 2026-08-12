{
  pkgs,
  source,
  buzz-desktop-frontend,
  buzz-desktop-sidecars,
}:

if !(pkgs.stdenv.hostPlatform.isLinux || pkgs.stdenv.hostPlatform.isDarwin) then
  { }
else
  let
    data = pkgs.lib.importJSON ./hashes.json;

    rustToolchain = pkgs.rust-bin.stable.${source.rustVersion}.default;
    rustPlatform = pkgs.makeRustPlatform {
      cargo = rustToolchain;
      rustc = rustToolchain;
    };
    rustTarget = pkgs.stdenv.hostPlatform.rust.rustcTarget;

    sherpaOnnxArchives = pkgs.callPackage ./sherpa-onnx.nix { };

    baseArgs = {
      pname = "buzz-desktop";
      inherit (source) version src;
      inherit (data) cargoHash;
      cargoRoot = "desktop/src-tauri";
      strictDeps = true;

      postPatch = prepareDesktop;

      nativeBuildInputs = [
        pkgs.cmake
        pkgs.perl
        pkgs.pkg-config
      ];

      env = {
        AWS_LC_SYS_CMAKE_BUILDER = 1;
        SHERPA_ONNX_ARCHIVE_DIR = sherpaOnnxArchives;
      };

      doCheck = false;

      meta = {
        description = "Desktop client for Buzz";
        homepage = "https://github.com/block/buzz";
        # sherpa-onnx statically links GPL-3.0-or-later eSpeak NG.
        license = pkgs.lib.licenses.gpl3Plus;
        mainProgram = "buzz-desktop";
        sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
      };
    };

    prepareDesktop = ''
      rm -rf desktop/dist
      cp -R ${buzz-desktop-frontend} desktop/dist
      chmod -R u+w desktop/dist

      mkdir -p desktop/src-tauri/binaries
      for executable in \
        buzz \
        buzz-acp \
        buzz-agent \
        buzz-backend-kubernetes \
        buzz-dev-mcp \
        git-credential-nostr
      do
        install -Dm755 \
          "${buzz-desktop-sidecars}/bin/$executable" \
          "desktop/src-tauri/binaries/$executable-${rustTarget}"
      done

      substituteInPlace desktop/src-tauri/tauri.conf.json \
        --replace-fail '"beforeBuildCommand": "pnpm build"' '"beforeBuildCommand": null'
    '';

    packageFile = if pkgs.stdenv.hostPlatform.isLinux then ./linux.nix else ./darwin.nix;

    buzz-desktop = import packageFile {
      inherit
        baseArgs
        pkgs
        rustPlatform
        rustTarget
        rustToolchain
        ;
      inherit (pkgs) lib;
    };
  in
  buzz-desktop
