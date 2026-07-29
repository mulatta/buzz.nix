{ buildBuzzFrontend }:

buildBuzzFrontend {
  pname = "buzz-desktop-frontend";
  workspace = "buzz";
  sourceDir = "desktop";
  metaDescription = "Frontend bundle embedded in Buzz Desktop";
}
