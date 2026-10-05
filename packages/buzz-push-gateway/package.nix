{ buildBuzzRust }:

buildBuzzRust {
  pname = "buzz-push-gateway";
  metaDescription = "Capability-gated APNs push gateway for Buzz mobile clients";
  # Keep personal-dev-app-attest disabled; production is the upstream default.
  installCheckPhase = ''
    test -x "$out/bin/buzz-push-gateway"
    # Migration mode must reject missing configuration before any DB access.
    if env -i "$out/bin/buzz-push-gateway" --migrate-only > migration-error 2>&1; then
      echo "Migration unexpectedly succeeded without DATABASE_URL" >&2
      exit 1
    fi
    grep -F 'NotPresent' migration-error
  '';
}
