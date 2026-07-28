{
  pkgs,
  source,
  buzz-cli,
  buzz-acp,
  buzz-agent,
  buzz-dev-mcp,
}:

pkgs.symlinkJoin {
  name = "buzz-agent-tools-${source.version}";
  paths = [
    buzz-cli
    buzz-acp
    buzz-agent
    buzz-dev-mcp
  ];
  meta = buzz-cli.meta // {
    description = "Buzz command-line and agent integration tools";
  };
}
