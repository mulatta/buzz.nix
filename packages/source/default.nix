{
  fetchFromGitHub,
  lib,
}:

let
  data = lib.importJSON ./hashes.json;

  src = fetchFromGitHub {
    owner = "block";
    repo = "buzz";
    inherit (data) rev hash;
  };
in
{
  inherit src;
  inherit (data)
    version
    relayVersion
    rustVersion
    rev
    rootCargoHash
    desktopCargoHash
    ;
}
