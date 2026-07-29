{
  buildBuzzRust,
  source,
}:

buildBuzzRust {
  pname = "buzz-server-binaries";
  version = source.relayVersion;

  targets = [
    {
      package = "buzz-relay";
      binary = "buzz-relay";
    }
    {
      package = "buzz-admin";
      binary = "buzz-admin";
    }
    {
      package = "buzz-pair-relay";
      binary = "buzz-pair-relay";
    }
  ];

  needsOpenSSL = false;
  mainProgram = null;

  installCheckPhase = ''
    test -x "$out/bin/buzz-relay"
    "$out/bin/buzz-admin" --help >/dev/null
    test -x "$out/bin/buzz-pair-relay"
  '';

  metaDescription = "Buzz relay server and administration tools";
}
