{
  lib,
  pkgs,
  source,
}:

let
  buzzRust = lib.buzz.mkBuzzRustPackage { inherit lib pkgs source; };
in
buzzRust.mkAgentTool {
  pname = "buzz-dev-mcp";
  package = "buzz-dev-mcp";
  binary = "buzz-dev-mcp";
  metaDescription = "MCP server providing shell and file-edit tools for Buzz";
}
