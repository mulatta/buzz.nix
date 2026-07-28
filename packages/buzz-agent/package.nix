{
  lib,
  pkgs,
  source,
}:

let
  buzzRust = lib.buzz.mkBuzzRustPackage { inherit lib pkgs source; };
in
buzzRust.mkAgentTool {
  pname = "buzz-agent";
  package = "buzz-agent";
  binary = "buzz-agent";
  metaDescription = "Minimal ACP-compliant LLM agent for Buzz";
}
