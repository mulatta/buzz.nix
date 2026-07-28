{
  lib,
  pkgs,
  source,
}:

let
  buzzRust = lib.buzz.mkBuzzRustPackage { inherit lib pkgs source; };
in
buzzRust.mkAgentTool {
  pname = "git-credential-nostr";
  package = "git-credential-nostr";
  binary = "git-credential-nostr";
  metaDescription = "Git credential helper for Buzz NIP-98 authentication";
  installCheckPhase = ''
    test -z "$(printf '\n' | "$out/bin/git-credential-nostr" get)"
  '';
}
