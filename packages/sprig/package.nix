{ buildBuzzRust, source }:

buildBuzzRust {
  pname = "sprig";
  version = source.sprigVersion;
  metaDescription = "All-in-one Buzz ACP harness, agent, and developer MCP";

  installCheckPhase = ''
    "$out/bin/sprig" --help >/dev/null
    test "$("$out/bin/sprig" --version)" = "sprig ${source.sprigVersion}"
  '';
}
