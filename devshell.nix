{ pkgs, formatter }:

pkgs.mkShellNoCC {
  packages = [
    # Repository maintenance
    pkgs.bash
    pkgs.coreutils
    pkgs.gh
    pkgs.git
    pkgs.gnugrep
    pkgs.gnused
    pkgs.jq
    pkgs.python3

    # Nix build UX
    pkgs.nix-output-monitor

    # Formatter and Nix linters
    formatter
  ];
}
