{ buildBuzzRust }:

buildBuzzRust {
  pname = "git-credential-nostr";
  metaDescription = "Git credential helper for Buzz NIP-98 authentication";
  installCheckPhase = ''
    test -z "$(printf '\n' | "$out/bin/git-credential-nostr" get)"
  '';
}
