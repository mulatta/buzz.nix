{
  lib,
  pkgs,
  source,
}:

let
  buzzRust = lib.buzz.mkBuzzRustPackage { inherit lib pkgs source; };
in
buzzRust.mkAgentTool {
  pname = "buzz-cli";
  package = "buzz-cli";
  binary = "buzz";
  metaDescription = "Agent-first CLI for Buzz relay";
  installCheckPhase = ''
    "$out/bin/buzz" --help >/dev/null
  '';
}
