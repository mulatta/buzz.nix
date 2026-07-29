{ buildBuzzFrontend }:

buildBuzzFrontend {
  pname = "buzz-web";
  workspace = "buzz-web";
  sourceDir = "web";
  metaDescription = "Web client for Buzz relay";
}
