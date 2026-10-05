{ buildBuzzRust, pkgs }:

buildBuzzRust {
  pname = "git-sign-nostr";
  needsOpenSSL = false;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postInstall = ''
    wrapProgram "$out/bin/git-sign-nostr" --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.gitMinimal ]}
  '';
  metaDescription = "Nostr signing backend for Git commits and tags";
  installCheckPhase = ''
    # Public upstream test key; never use this identity outside the test.
    printf 'test payload\n' > payload
    NOSTR_PRIVATE_KEY=0000000000000000000000000000000000000000000000000000000000000003 \
      "$out/bin/git-sign-nostr" --status-fd=2 -bsau \
      f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9 \
      < payload > signature
    "$out/bin/git-sign-nostr" --status-fd=1 --verify signature - < payload
  '';
}
