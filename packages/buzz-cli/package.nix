{ buildBuzzRust }:

buildBuzzRust {
  pname = "buzz-cli";
  binary = "buzz";
  metaDescription = "Agent-first CLI for Buzz relay";
  installCheckPhase = ''
    "$out/bin/buzz" --help >/dev/null
  '';
}
