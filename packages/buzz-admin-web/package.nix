{ buildBuzzFrontend }:

buildBuzzFrontend {
  pname = "buzz-admin-web";
  workspace = "buzz-admin-web";
  sourceDir = "admin-web";
  metaDescription = "Administration interface for Buzz relay";
}
