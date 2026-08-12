{
  pkgs,
  source,
  buzz-cli,
  buzz-acp,
  buzz-agent,
  buzz-backend-kubernetes,
  buzz-dev-mcp,
  git-credential-nostr,
}:

pkgs.symlinkJoin {
  name = "buzz-desktop-sidecars-${source.version}";
  paths = [
    buzz-cli
    buzz-acp
    buzz-agent
    buzz-backend-kubernetes
    buzz-dev-mcp
    git-credential-nostr
  ];
  postBuild = ''
    for executable in \
      buzz \
      buzz-acp \
      buzz-agent \
      buzz-backend-kubernetes \
      buzz-dev-mcp \
      git-credential-nostr
    do
      test -x "$out/bin/$executable"
    done

    test "$(find "$out/bin" -mindepth 1 -maxdepth 1 | wc -l)" -eq 6
  '';
  meta = buzz-cli.meta // {
    description = "Sidecar binaries required by Buzz Desktop";
  };
}
