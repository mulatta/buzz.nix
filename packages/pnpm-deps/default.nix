{
  fetchPnpmDeps,
  pkgs,
  source,
}:

let
  pnpm = pkgs.pnpm_11.override {
    nodejs-slim = pkgs.nodejs_24;
  };
in
fetchPnpmDeps {
  pname = "buzz-workspace";
  inherit (source) version src;
  inherit pnpm;
  fetcherVersion = 4;
  hash = "sha256-Tboy+MG/VvdxUpJw7Xv0oubK58MIpvChvbU30uO4M4A=";
}
