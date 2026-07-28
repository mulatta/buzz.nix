{
  lib,
  pkgs,
  source,
}:

let
  buzzRust = lib.buzz.mkBuzzRustPackage { inherit lib pkgs source; };
in
buzzRust.mkAgentTool {
  pname = "buzz-acp";
  package = "buzz-acp";
  binary = "buzz-acp";
  metaDescription = "ACP harness that bridges Buzz events to AI agents";
  installCheckPhase = ''
    "$out/bin/buzz-acp" --help >/dev/null
  '';
}
