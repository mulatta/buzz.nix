{
  baseArgs,
  lib,
  pkgs,
  rustPlatform,
  rustTarget,
  rustToolchain,
}:

let
  tauriHook = pkgs.cargo-tauri.hook.override { cargo = rustToolchain; };

  runtimePrograms = [
    pkgs.bashNonInteractive
    pkgs.ffmpeg-headless
    pkgs.gitMinimal
  ];
  runtimePath = lib.makeBinPath runtimePrograms;
  caBundle = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
in
rustPlatform.buildRustPackage (
  baseArgs
  // {
    cargoBuildFlags = [
      "--package"
      "buzz-desktop"
      "--target"
      rustTarget
    ];
    nativeBuildInputs = baseArgs.nativeBuildInputs ++ [
      tauriHook
      pkgs.libplist
      pkgs.makeBinaryWrapper
    ];
    buildPhase = "tauriBuildHook";
    installPhase = ''
      cd desktop/src-tauri
      tauriInstallHook
    '';
    doNotPostBuildInstallCargoBinaries = true;
    tauriBuildFlags = [ "--no-sign" ];

    postFixup = ''
      app="$out/Applications/Buzz.app"
      main="$app/Contents/MacOS/buzz-desktop"

      wrapProgram "$main" \
        --prefix PATH : "${runtimePath}" \
        --set-default SSL_CERT_FILE "${caBundle}" \
        --set-default BUZZ_SHELL "${pkgs.bashNonInteractive}/bin/bash"

      mkdir -p "$out/bin"
      ln -s "$main" "$out/bin/buzz-desktop"
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      app="$out/Applications/Buzz.app"
      mainDir="$app/Contents/MacOS"
      test -x "$mainDir/buzz-desktop"
      for executable in \
        buzz \
        buzz-acp \
        buzz-agent \
        buzz-dev-mcp \
        git-credential-nostr
      do
        test -x "$mainDir/$executable"
      done
      test "$out/bin/buzz-desktop" -ef "$mainDir/buzz-desktop"

      for runtimeInput in \
        ${runtimePath} \
        ${caBundle} \
        ${pkgs.bashNonInteractive}/bin/bash
      do
        grep -a -F "$runtimeInput" "$mainDir/buzz-desktop" >/dev/null
      done
      test -x ${pkgs.bashNonInteractive}/bin/bash
      test -x ${pkgs.ffmpeg-headless}/bin/ffmpeg
      test -x ${pkgs.gitMinimal}/bin/git
      test -f ${caBundle}

      infoPlist="$app/Contents/Info.plist"
      test -f "$infoPlist"
      ${pkgs.libplist}/bin/plistutil -f xml -i "$infoPlist" -o "$TMPDIR/Info.plist.xml"
      for key in \
        NSMicrophoneUsageDescription \
        NSCameraUsageDescription \
        NSLocalNetworkUsageDescription
      do
        grep -F "<key>$key</key>" "$TMPDIR/Info.plist.xml" >/dev/null
      done
      grep -A1 -F '<key>CFBundleExecutable</key>' "$TMPDIR/Info.plist.xml" \
        | grep -F '<string>buzz-desktop</string>' >/dev/null
      grep -A1 -F '<key>CFBundleIdentifier</key>' "$TMPDIR/Info.plist.xml" \
        | grep -F '<string>xyz.block.buzz.app</string>' >/dev/null
      grep -A3 -F '<key>CFBundleURLSchemes</key>' "$TMPDIR/Info.plist.xml" \
        | grep -F '<string>buzz</string>' >/dev/null

      otool -L "$mainDir/.buzz-desktop-wrapped" >"$TMPDIR/otool.txt"
      ! grep -F '/build/' "$TMPDIR/otool.txt"
    '';

    meta = baseArgs.meta // {
      platforms = [ "aarch64-darwin" ];
    };
  }
)
