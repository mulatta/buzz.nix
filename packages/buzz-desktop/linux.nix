{
  baseArgs,
  lib,
  pkgs,
  rustPlatform,
  rustTarget,
  rustToolchain,
}:

let
  commonArgs = baseArgs // {
    buildInputs = [
      pkgs.alsa-lib
      pkgs.gtk3
      pkgs.libopus
      pkgs.libsoup_3
      pkgs.webkitgtk_4_1
    ];
  };

  tauriHook = pkgs.cargo-tauri.hook.override { cargo = rustToolchain; };

  gstreamerPlugins = with pkgs.gst_all_1; [
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-libav
  ];
  gstreamerPluginPath = lib.makeSearchPath "lib/gstreamer-1.0" gstreamerPlugins;

  runtimePrograms = [
    pkgs.bashNonInteractive
    pkgs.ffmpeg-headless
    pkgs.gitMinimal
  ];
  runtimePath = lib.makeBinPath runtimePrograms;
  caBundle = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  registrySetup = ''
    if [[ -z "''${GST_REGISTRY_1_0:-}" ]]; then
      cacheHome="''${XDG_CACHE_HOME:-''${HOME:?HOME must be set}/.cache}"
      export GST_REGISTRY_1_0="$cacheHome/buzz/gstreamer-1.0/registry-${rustTarget}.bin"
      ${pkgs.coreutils}/bin/mkdir -p "$cacheHome/buzz/gstreamer-1.0"
    fi
  '';
in
rustPlatform.buildRustPackage (
  commonArgs
  // {
    cargoBuildFlags = [
      "--package"
      "buzz-desktop"
      "--target"
      rustTarget
    ];
    nativeBuildInputs = commonArgs.nativeBuildInputs ++ [
      tauriHook
      pkgs.makeWrapper
      pkgs.wrapGAppsHook3
    ];
    buildInputs = commonArgs.buildInputs ++ [ pkgs.glib-networking ] ++ gstreamerPlugins;
    buildPhase = "tauriBuildHook";
    installPhase = ''
      cd desktop/src-tauri
      tauriInstallHook
    '';
    doNotPostBuildInstallCargoBinaries = true;
    tauriBuildFlags = [ "--no-sign" ];

    preFixup = ''
      gappsWrapperArgs+=(
        --prefix PATH : "${runtimePath}"
        --set-default SSL_CERT_FILE "${caBundle}"
        --set-default BUZZ_SHELL "${pkgs.bashNonInteractive}/bin/bash"
        --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${gstreamerPluginPath}"
      )
    '';

    postFixup = ''
      wrapProgramShell "$out/bin/buzz-desktop" \
        --run ${lib.escapeShellArg registrySetup}
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      test -x "$out/bin/buzz-desktop"
      for executable in \
        buzz \
        buzz-acp \
        buzz-agent \
        buzz-dev-mcp \
        git-credential-nostr
      do
        test -x "$out/bin/$executable"
      done

      desktopFile=$(find "$out/share/applications" -name '*.desktop' -print -quit)
      test -n "$desktopFile"
      grep -F 'x-scheme-handler/buzz' "$desktopFile"
      find "$out/share/icons" -type f -print -quit | grep -q .

      for runtimeInput in \
        ${runtimePath} \
        ${caBundle} \
        ${gstreamerPluginPath} \
        ${pkgs.cargo-tauri.gst-plugin}/lib/gstreamer-1.0
      do
        grep -R -a -F "$runtimeInput" "$out/bin" >/dev/null
      done
      grep -F 'GST_REGISTRY_1_0' "$out/bin/buzz-desktop"

      test -x ${pkgs.bashNonInteractive}/bin/bash
      test -x ${pkgs.ffmpeg-headless}/bin/ffmpeg
      test -x ${pkgs.gitMinimal}/bin/git
      test -f ${caBundle}

      export HOME="$TMPDIR/home"
      export XDG_CACHE_HOME="$HOME/.cache"
      mkdir -p "$XDG_CACHE_HOME"
      export GST_PLUGIN_SYSTEM_PATH_1_0="${gstreamerPluginPath}:${pkgs.cargo-tauri.gst-plugin}/lib/gstreamer-1.0"
      export GST_REGISTRY_1_0="$XDG_CACHE_HOME/gstreamer-registry.bin"
      for element in playbin3 mpg123audiodec v4l2src avdec_h264; do
        ${pkgs.gst_all_1.gstreamer}/bin/gst-inspect-1.0 "$element" >/dev/null
      done

      ldd "$out/bin/.buzz-desktop-wrapped" | grep -F 'libwebkit2gtk-4.1.so'
      ldd "$out/bin/.buzz-desktop-wrapped" | grep -F 'libasound.so'
      ldd "$out/bin/.buzz-desktop-wrapped" | grep -F 'libopus.so'
    '';

    meta = baseArgs.meta // {
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  }
)
