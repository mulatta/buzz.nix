{
  fetchFromGitHub,
  lib,
}:

let
  data = lib.importJSON ./pin.json;

  # Keep source-derived metadata in pin.json so evaluation does not need to read
  # Cargo.toml or rust-toolchain.toml from the fetched source.
  src = fetchFromGitHub {
    owner = "block";
    repo = "buzz";
    rev = data.tag;
    inherit (data) hash;
  };
in
{
  inherit src;
  inherit (data)
    version
    relayVersion
    rustVersion
    ;
}
