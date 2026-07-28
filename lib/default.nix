_final: _prev: {
  buzz = {
    mkBuzzFrontendPackage = import ./mk-buzz-frontend-package.nix;
    mkBuzzRustPackage = import ./mk-buzz-rust-package.nix;
  };
}
