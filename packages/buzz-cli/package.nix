{ buildBuzzRust, pkgs }:

buildBuzzRust {
  pname = "buzz-cli";
  binary = "buzz";
  metaDescription = "Agent-first CLI for Buzz relay";

  nativeBuildInputs = [ pkgs.installAgentSkills ];
  dontInstallAgentSkills = true;
  postInstall = ''
    installSkill .agents/skills/sprout-cli
  '';

  installCheckPhase = ''
    "$out/bin/buzz" --help >/dev/null
    test -s "$out/share/skills/buzz-cli/sprout-cli/SKILL.md"
    test "$(find "$out/share/skills" -name SKILL.md | wc -l)" -eq 1
  '';
}
