_:

{
  projectRootFile = "flake.nix";

  programs = {
    deadnix.enable = true;
    keep-sorted.enable = true;
    mdformat.enable = true;
    nixfmt.enable = true;
    ruff-check.enable = true;
    ruff-format.enable = true;
    statix.enable = true;
    yamlfmt.enable = true;
  };
}
