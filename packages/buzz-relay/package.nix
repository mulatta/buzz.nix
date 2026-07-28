{
  lib,
  pkgs,
  source,
  buzz-server-binaries,
  buzz-web,
  buzz-admin-web,
}:

let
  runtimeTools = with pkgs; [
    bashNonInteractive
    coreutils
    curl
    gitMinimal
    gnused
    openssl
  ];
  runtimePath = lib.makeBinPath runtimeTools;
  caBundle = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "buzz-relay";
  version = source.relayVersion;
  strictDeps = true;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/buzz"

    makeWrapper ${buzz-server-binaries}/bin/buzz-relay "$out/bin/buzz-relay" \
      --set-default BUZZ_WEB_DIR "$out/share/buzz/web" \
      --set-default BUZZ_ADMIN_WEB_DIR "$out/share/buzz/admin-web" \
      --set-default SSL_CERT_FILE ${caBundle} \
      --prefix PATH : ${runtimePath}

    makeWrapper ${buzz-server-binaries}/bin/buzz-admin "$out/bin/buzz-admin" \
      --set-default SSL_CERT_FILE ${caBundle}
    makeWrapper ${buzz-server-binaries}/bin/buzz-pair-relay "$out/bin/buzz-pair-relay" \
      --set-default SSL_CERT_FILE ${caBundle}

    ln -s ${buzz-web} "$out/share/buzz/web"
    ln -s ${buzz-admin-web} "$out/share/buzz/admin-web"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/buzz-relay"
    test -x "$out/bin/buzz-admin"
    test -x "$out/bin/buzz-pair-relay"
    test -f "$out/share/buzz/web/index.html"
    test -f "$out/share/buzz/admin-web/index.html"
    test -s ${caBundle}

    grep -F "$out/share/buzz/web" "$out/bin/buzz-relay" >/dev/null
    grep -F "$out/share/buzz/admin-web" "$out/bin/buzz-relay" >/dev/null
    for binary in buzz-relay buzz-admin buzz-pair-relay; do
      grep -F ${caBundle} "$out/bin/$binary" >/dev/null
    done
    "$out/bin/buzz-admin" --help >/dev/null

    for tool in ${lib.escapeShellArgs (map toString runtimeTools)}; do
      grep -F "$tool/bin" "$out/bin/buzz-relay" >/dev/null
    done

    env -i PATH=${runtimePath} git --version >/dev/null
    gitExecPath=$(env -i PATH=${runtimePath} git --exec-path)
    for command in receive-pack upload-pack merge-base pack-objects index-pack update-ref; do
      test -x "$gitExecPath/git-$command"
    done
    for command in bash curl mktemp sort cat date rm sed; do
      env -i PATH=${runtimePath} "$command" --version >/dev/null
    done
    env -i PATH=${runtimePath} openssl version >/dev/null
  '';

  meta = {
    description = "Buzz relay server with bundled web interfaces";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    mainProgram = "buzz-relay";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
