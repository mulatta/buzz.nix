{
  module,
  pkgs,
}:

let
  ownerPubkey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

  relayFixture = pkgs.writeShellApplication {
    name = "buzz-relay";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      env | sort > "$PWD/buzz-relay.env"
      touch "$BUZZ_GIT_REPO_PATH/write-test"
      touch "$BUZZ_GIT_PACK_CACHE_PATH/write-test"
      exec sleep infinity
    '';
  };

  pairingFixture = pkgs.writeShellApplication {
    name = "buzz-pair-relay";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      exec sleep infinity
    '';
  };

  testPackage = pkgs.symlinkJoin {
    name = "buzz-relay-test-package";
    paths = [
      relayFixture
      pairingFixture
    ];
    meta.mainProgram = "buzz-relay";
  };
in
pkgs.testers.runNixOSTest {
  name = "buzz-relay-module";

  nodes.machine = {
    imports = [ module ];

    environment.systemPackages = [ pkgs.nftables ];

    systemd.tmpfiles.rules = [
      "d /run/secrets 0755 root root -"
      "f /run/secrets/buzz-relay.env 0600 root root - TEST_SECRET=fixture"
    ];

    services.buzz-relay = {
      enable = true;
      package = testPackage;
      relayUrl = "wss://buzz.example";
      inherit ownerPubkey;
      environmentFiles = [ "/run/secrets/buzz-relay.env" ];
      media = {
        baseUrl = "https://buzz.example/media";
        s3Endpoint = "http://127.0.0.1:9000";
      };
      adminHost = "admin.buzz.example";
      corsOrigins = [ "https://buzz.example" ];
      environment.BUZZ_DB_POOL_SIZE = "80";
      openFirewall = true;
      pairingRelay = {
        enable = true;
        url = "wss://pair.buzz.example";
        openFirewall = true;
      };
    };
  };

  testScript = ''
    start_all()

    machine.wait_for_unit("buzz-relay.service")
    machine.wait_for_unit("buzz-pair-relay.service")

    machine.succeed("systemctl cat buzz-relay.service | grep -F 'EnvironmentFile=/run/secrets/buzz-relay.env'")
    machine.succeed("systemctl show buzz-relay.service -p User --value | grep -Fx buzz-relay")
    machine.succeed("systemctl show buzz-relay.service -p Group --value | grep -Fx buzz-relay")
    machine.succeed("systemctl show buzz-relay.service -p StateDirectory --value | grep -Fx buzz-relay")
    machine.succeed("systemctl show buzz-relay.service -p CacheDirectory --value | grep -Fx buzz-relay")
    machine.succeed("systemctl cat buzz-relay.service | grep -Fx 'CapabilityBoundingSet='")
    machine.succeed("systemctl cat buzz-relay.service | grep -Fx 'ProtectSystem=strict'")
    machine.succeed("systemctl cat buzz-relay.service | grep -Fx 'NoNewPrivileges=true'")
    machine.succeed("systemctl cat buzz-pair-relay.service | grep -Fx 'DynamicUser=true'")
    machine.succeed("test $(stat -c %U:%G:%a /var/lib/buzz-relay) = buzz-relay:buzz-relay:700")
    machine.succeed("test $(stat -c %U:%G:%a /var/cache/buzz-relay) = buzz-relay:buzz-relay:700")
    machine.succeed("test $(stat -c %U:%G:%a /var/lib/buzz-relay/repos) = buzz-relay:buzz-relay:700")
    machine.succeed("test $(stat -c %U:%G:%a /var/cache/buzz-relay/git-pack-cache) = buzz-relay:buzz-relay:700")
    machine.succeed("test -f /var/lib/buzz-relay/repos/write-test")
    machine.succeed("test -f /var/cache/buzz-relay/git-pack-cache/write-test")

    relay_env = set(machine.succeed("cat /var/lib/buzz-relay/buzz-relay.env").splitlines())
    for expected in [
        "BUZZ_BIND_ADDR=127.0.0.1:3000",
        "BUZZ_HEALTH_PORT=8080",
        "BUZZ_METRICS_PORT=9102",
        "RELAY_URL=wss://buzz.example",
        "RELAY_OWNER_PUBKEY=${ownerPubkey}",
        "BUZZ_AUTO_MIGRATE=true",
        "BUZZ_REQUIRE_AUTH_TOKEN=true",
        "BUZZ_REQUIRE_RELAY_MEMBERSHIP=true",
        "BUZZ_REQUIRE_MEDIA_GET_AUTH=true",
        "BUZZ_ALLOW_NIP_OA_AUTH=true",
        "BUZZ_PUBKEY_ALLOWLIST=false",
        "BUZZ_MAX_CONNECTIONS=10000",
        "BUZZ_MAX_CONCURRENT_HANDLERS=1024",
        "BUZZ_SEND_BUFFER=1000",
        "BUZZ_HUDDLE_AUDIO_AVAILABLE=true",
        "BUZZ_PUSH_GATEWAY_DELIVERY_URL=",
        "BUZZ_MEDIA_BASE_URL=https://buzz.example/media",
        "BUZZ_S3_ENDPOINT=http://127.0.0.1:9000",
        "BUZZ_S3_BUCKET=buzz-media",
        "BUZZ_S3_REGION=us-east-1",
        "BUZZ_GIT_REPO_PATH=/var/lib/buzz-relay/repos",
        "BUZZ_GIT_PACK_CACHE_PATH=/var/cache/buzz-relay/git-pack-cache",
        "BUZZ_GIT_MAX_PACK_BYTES=524288000",
        "BUZZ_GIT_MAX_REPO_BYTES=1048576000",
        "BUZZ_GIT_PACK_CACHE_MAX_BYTES=5368709120",
        "BUZZ_GIT_PACK_CACHE_MAX_CONCURRENT_POPULATIONS=2",
        "BUZZ_GIT_MAX_REPOS_PER_PUBKEY=100",
        "BUZZ_GIT_MAX_CONCURRENT_OPS=20",
        "BUZZ_ADMIN_HOST=admin.buzz.example",
        "BUZZ_CORS_ORIGINS=https://buzz.example",
        "BUZZ_PAIRING_RELAY_URL=wss://pair.buzz.example",
        "BUZZ_DB_POOL_SIZE=80",
        "RUST_LOG=buzz_relay=info",
        "TEST_SECRET=fixture",
    ]:
        t.assertIn(expected, relay_env)

    pair_env = machine.succeed("systemctl show buzz-pair-relay.service -p Environment --value")
    t.assertIn("BUZZ_PAIR_RELAY_BIND_ADDR=127.0.0.1:5000", pair_env)

    firewall = machine.succeed("nft list ruleset")
    for port in (3000, 5000):
        t.assertRegex(firewall, rf"tcp dport (?:{port}|\{{[^}}]*\b{port}\b[^}}]*\}})")
    for port in (8080, 9102):
        t.assertNotRegex(firewall, rf"tcp dport (?:{port}|\{{[^}}]*\b{port}\b[^}}]*\}})")
  '';
}
