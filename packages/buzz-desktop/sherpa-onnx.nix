{
  fetchurl,
  lib,
  linkFarm,
  stdenv,
}:

let
  data = lib.importJSON ./hashes.json;
  system = stdenv.hostPlatform.system;
  archive =
    data.archives.${system}
      or (throw "sherpa-onnx ${data.version} has no prebuilt archive for ${system}");

  archiveFile = fetchurl {
    name = archive.file;
    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/v${data.version}/${archive.file}";
    inherit (archive) hash;
  };
in
linkFarm "sherpa-onnx-${data.version}-archives-${system}" [
  {
    name = archive.file;
    path = archiveFile;
  }
]
