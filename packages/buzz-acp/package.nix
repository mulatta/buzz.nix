{ buildBuzzRust }:

buildBuzzRust {
  pname = "buzz-acp";
  metaDescription = "ACP harness that bridges Buzz events to AI agents";
  installCheckPhase = ''
    "$out/bin/buzz-acp" --help >/dev/null
  '';
}
