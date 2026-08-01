{
  lib,
  module,
  package,
  pkgs,
}:

let
  rustfsPackage = pkgs.rustfs.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [ ./patches/rustfs-buzz-cas-lock.patch ];
    doCheck = false;
  });

  ownerPrivateKey = "0000000000000000000000000000000000000000000000000000000000000001";
  ownerPubkey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
  hookSecret = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
  s3AccessKey = "BKIKJAA5BMMU2RHO6IBB";
  s3SecretKey = "V7f1CwQqAcwo80UEIJEjc5gVQUSSx5ohQ9GSrr12";
  bucket = "buzz-media";

  secretsSetup = pkgs.writeShellApplication {
    name = "buzz-test-secrets";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      umask 077
      install -d -m 0700 /run/keys

      cat > /run/keys/rustfs.env <<'EOF'
      RUSTFS_ACCESS_KEY=${s3AccessKey}
      RUSTFS_SECRET_KEY=${s3SecretKey}
      EOF

      cat > /run/keys/buzz-relay.env <<'EOF'
      DATABASE_URL=postgres://buzz@127.0.0.1:5432/buzz
      REDIS_URL=redis://127.0.0.1:6379
      BUZZ_RELAY_PRIVATE_KEY=${ownerPrivateKey}
      BUZZ_GIT_HOOK_HMAC_SECRET=${hookSecret}
      BUZZ_S3_ACCESS_KEY=${s3AccessKey}
      BUZZ_S3_SECRET_KEY=${s3SecretKey}
      EOF

      chmod 0400 /run/keys/rustfs.env /run/keys/buzz-relay.env
    '';
  };

  s3Probe =
    pkgs.writers.writePython3 "buzz-s3-probe"
      {
        libraries = [ pkgs.python3Packages.boto3 ];
      }
      ''
        import time
        from pathlib import Path

        import boto3
        from botocore.config import Config
        from botocore.exceptions import BotoCoreError, ClientError


        def load_environment(path: Path) -> dict[str, str]:
            values: dict[str, str] = {}
            for line in path.read_text().splitlines():
                key, value = line.split("=", 1)
                values[key] = value
            return values


        credentials = load_environment(Path("/run/keys/rustfs.env"))
        client = boto3.client(
            "s3",
            endpoint_url="http://127.0.0.1:9000",
            aws_access_key_id=credentials["RUSTFS_ACCESS_KEY"],
            aws_secret_access_key=credentials["RUSTFS_SECRET_KEY"],
            region_name="us-east-1",
            config=Config(
                connect_timeout=1,
                read_timeout=5,
                retries={"max_attempts": 2, "mode": "standard"},
                s3={"addressing_style": "path"},
            ),
        )

        last_error: Exception | None = None
        for _attempt in range(90):
            try:
                response = client.list_buckets()
                break
            except (BotoCoreError, ClientError) as error:
                last_error = error
                time.sleep(1)
        else:
            raise RuntimeError("RustFS did not become ready") from last_error

        buckets = {entry["Name"] for entry in response.get("Buckets", [])}
        if "${bucket}" not in buckets:
            client.create_bucket(Bucket="${bucket}")

        key = "nixos-test/roundtrip"
        payload = b"buzz-rustfs-roundtrip"
        client.put_object(Bucket="${bucket}", Key=key, Body=payload)
        result = client.get_object(Bucket="${bucket}", Key=key)
        try:
            received = result["Body"].read()
        finally:
            result["Body"].close()
        if received != payload:
            raise RuntimeError(f"S3 roundtrip mismatch: {received!r}")
        client.delete_object(Bucket="${bucket}", Key=key)
        print("RustFS S3 roundtrip passed")
      '';
  s3ProbeExe = toString s3Probe;
in
pkgs.testers.runNixOSTest {
  name = "buzz-relay-rustfs-patched-integration";
  meta.timeout = 900;

  nodes.machine =
    { config, ... }:
    {
      imports = [ module ];

      virtualisation = {
        cores = 2;
        diskSize = 4096;
        memorySize = 3072;
      };

      networking.extraHosts = ''
        127.0.0.1 relay.test admin.test pair.test
      '';

      environment.systemPackages = [
        config.services.postgresql.package
        pkgs.curl
        pkgs.jq
        pkgs.util-linux
      ];

      services.postgresql = {
        enable = true;
        enableTCPIP = true;
        ensureDatabases = [ "buzz" ];
        ensureUsers = [
          {
            name = "buzz";
            ensureDBOwnership = true;
          }
        ];
        authentication = ''
          host buzz buzz 127.0.0.1/32 trust
        '';
        settings.listen_addresses = lib.mkForce "127.0.0.1";
      };

      services.redis.servers.buzz = {
        enable = true;
        bind = "127.0.0.1";
        port = 6379;
      };

      services.rustfs = {
        enable = true;
        package = rustfsPackage;
        environmentFile = "/run/keys/rustfs.env";
        settings.RUSTFS_VOLUMES = "/var/lib/rustfs";
      };

      services.buzz-relay = {
        enable = true;
        relayUrl = "ws://relay.test:3000";
        inherit ownerPubkey;
        adminHost = "admin.test";
        corsOrigins = [
          "http://relay.test:3000"
          "http://admin.test"
        ];
        environmentFiles = [ "/run/keys/buzz-relay.env" ];
        environment = {
          BUZZ_GIT_CONFORMANCE_PROBE = "true";
          BUZZ_POOL_METRICS_INTERVAL_SECS = "1";
        };
        media = {
          baseUrl = "http://relay.test:3000/media";
          s3Endpoint = "http://127.0.0.1:9000";
          s3Bucket = bucket;
          s3Region = "us-east-1";
        };
        pairingRelay = {
          enable = true;
          url = "ws://pair.test:5000/pair";
        };
      };

      systemd.services.buzz-test-secrets = {
        description = "Create Buzz integration test secrets";
        wantedBy = [ "multi-user.target" ];
        before = [
          "rustfs.service"
          "rustfs-bucket.service"
          "buzz-relay.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = lib.getExe secretsSetup;
        };
      };

      systemd.services.rustfs = {
        requires = [ "buzz-test-secrets.service" ];
        after = [ "buzz-test-secrets.service" ];
      };

      systemd.services.rustfs-bucket = {
        description = "Initialize Buzz RustFS bucket";
        wantedBy = [ "multi-user.target" ];
        requires = [
          "buzz-test-secrets.service"
          "rustfs.service"
        ];
        after = [
          "buzz-test-secrets.service"
          "rustfs.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = s3ProbeExe;
          TimeoutStartSec = "120s";
        };
      };

      systemd.services.buzz-relay = {
        wants = [
          "postgresql.service"
          "redis-buzz.service"
        ];
        requires = [
          "buzz-test-secrets.service"
          "rustfs-bucket.service"
        ];
        after = [
          "buzz-test-secrets.service"
          "postgresql.service"
          "redis-buzz.service"
          "rustfs-bucket.service"
        ];
      };
    };

  testScript = ''
    import json
    import shlex


    def query(sql: str) -> str:
        return machine.succeed(
            "sudo -u postgres psql --dbname=buzz --tuples-only --no-align --command "
            + shlex.quote(sql)
        ).strip()


    start_all()

    machine.wait_for_unit("buzz-test-secrets.service")
    machine.wait_for_unit("postgresql.service")
    machine.wait_for_open_port(5432)
    machine.wait_for_unit("redis-buzz.service")
    machine.wait_for_open_port(6379)
    machine.wait_for_unit("rustfs.service")
    machine.wait_for_open_port(9000)
    machine.wait_for_unit("rustfs-bucket.service")
    machine.wait_for_unit("buzz-pair-relay.service")
    machine.wait_for_open_port(5000)
    machine.wait_until_succeeds("systemctl is-active --quiet buzz-relay.service", timeout=300)
    for port in (3000, 8080, 9102):
        machine.wait_for_open_port(port)

    journal = machine.succeed("journalctl -u buzz-relay.service -b --no-pager -o cat")
    t.assertIn("Database migrations complete", journal)
    t.assertIn("git object-store backend admitted: A3 conformance probe passed", journal)
    t.assertIn('"transport_drops":0', journal)
    t.assertNotIn("git conformance probe failed", journal)
    t.assertEqual(
        machine.succeed("systemctl show buzz-relay.service -p NRestarts --value").strip(),
        "0",
    )

    t.assertEqual(machine.succeed("curl -fsS http://127.0.0.1:8080/_liveness").strip(), "ok")
    readiness = json.loads(machine.succeed("curl -fsS http://127.0.0.1:8080/_readiness"))
    t.assertEqual(readiness, {"status": "ready"})
    machine.succeed("curl -fsS http://127.0.0.1:9102/metrics | grep -q '^buzz_'")

    nip11 = json.loads(
        machine.succeed(
            "curl -fsS -H 'Host: relay.test:3000' -H 'Accept: application/nostr+json' http://127.0.0.1:3000/"
        )
    )
    t.assertEqual(nip11["pairing_relay_url"], "ws://pair.test:5000/pair")
    t.assertEqual(nip11["self"], "${ownerPubkey}")
    t.assertIn(43, nip11["supported_nips"])
    t.assertNotIn("push", nip11)
    t.assertNotIn("nip-pl", nip11["supported_extensions"])

    machine.succeed(
        "curl -fsS -H 'Host: relay.test:3000' http://127.0.0.1:3000/invite/test-code -o /tmp/buzz-web.html"
    )
    machine.succeed("cmp /tmp/buzz-web.html ${package}/share/buzz/web/index.html")
    machine.fail("cmp /tmp/buzz-web.html ${package}/share/buzz/admin-web/index.html")
    machine.succeed(
        "curl -fsS -H 'Host: admin.test' -H 'Accept: text/html' http://127.0.0.1:3000/ -o /tmp/buzz-admin.html"
    )
    machine.succeed("cmp /tmp/buzz-admin.html ${package}/share/buzz/admin-web/index.html")
    machine.fail("cmp /tmp/buzz-admin.html ${package}/share/buzz/web/index.html")

    migration_count = int(query("SELECT count(*) FROM _sqlx_migrations"))
    t.assertGreater(migration_count, 0)
    t.assertEqual(
        query("SELECT COALESCE(bool_and(success), false)::text FROM _sqlx_migrations"),
        "true",
    )
    t.assertEqual(
        query("SELECT count(*) FROM communities WHERE host = 'relay.test:3000'"),
        "1",
    )
    t.assertEqual(
        query(
            "SELECT count(*) FROM relay_members rm "
            "JOIN communities c ON c.id = rm.community_id "
            "WHERE c.host = 'relay.test:3000' "
            "AND rm.pubkey = '${ownerPubkey}' AND rm.role = 'owner'"
        ),
        "1",
    )

    machine.succeed("${s3ProbeExe}")

    database_baseline = (
        migration_count,
        query("SELECT count(*) FROM communities WHERE host = 'relay.test:3000'"),
        query(
            "SELECT count(*) FROM relay_members rm "
            "JOIN communities c ON c.id = rm.community_id "
            "WHERE c.host = 'relay.test:3000' "
            "AND rm.pubkey = '${ownerPubkey}' AND rm.role = 'owner'"
        ),
    )
    machine.succeed("systemctl restart buzz-relay.service")
    for port in (3000, 8080, 9102):
        machine.wait_for_open_port(port)
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:8080/_readiness", timeout=120)
    restarted_journal = machine.succeed("journalctl -u buzz-relay.service -b --no-pager -o cat")
    t.assertGreaterEqual(
        restarted_journal.count("git object-store backend admitted: A3 conformance probe passed"),
        2,
    )
    t.assertGreaterEqual(restarted_journal.count("Database migrations complete"), 2)
    t.assertEqual(
        (
            int(query("SELECT count(*) FROM _sqlx_migrations")),
            query("SELECT count(*) FROM communities WHERE host = 'relay.test:3000'"),
            query(
                "SELECT count(*) FROM relay_members rm "
                "JOIN communities c ON c.id = rm.community_id "
                "WHERE c.host = 'relay.test:3000' "
                "AND rm.pubkey = '${ownerPubkey}' AND rm.role = 'owner'"
            ),
        ),
        database_baseline,
    )
    restarted_nip11 = json.loads(
        machine.succeed(
            "curl -fsS -H 'Host: relay.test:3000' -H 'Accept: application/nostr+json' http://127.0.0.1:3000/"
        )
    )
    t.assertEqual(restarted_nip11["self"], "${ownerPubkey}")
    t.assertNotIn("push", restarted_nip11)

    machine.succeed("systemctl stop redis-buzz.service")
    machine.succeed("systemctl is-active --quiet buzz-relay.service")
    t.assertEqual(machine.succeed("curl -fsS http://127.0.0.1:8080/_liveness").strip(), "ok")
    machine.wait_until_succeeds(
        "curl -sS -o /tmp/readiness.json -w '%{http_code}' http://127.0.0.1:8080/_readiness > /tmp/readiness.code; "
        "grep -qx 503 /tmp/readiness.code && grep -q 'postgres.*true' /tmp/readiness.json && grep -q 'redis.*false' /tmp/readiness.json",
        timeout=60,
    )
    machine.succeed("systemctl start redis-buzz.service")
    machine.wait_for_unit("redis-buzz.service")
    machine.wait_until_succeeds(
        "curl -fsS http://127.0.0.1:8080/_readiness | grep -q 'status.*ready'",
        timeout=120,
    )

    for path in (
        "/var/lib/buzz-relay",
        "/var/lib/buzz-relay/repos",
        "/var/cache/buzz-relay",
        "/var/cache/buzz-relay/git-pack-cache",
    ):
        machine.succeed(f"test $(stat -c %U:%G:%a {path}) = buzz-relay:buzz-relay:700")
    machine.succeed("test $(stat -c %U:%G:%a /run/keys/buzz-relay.env) = root:root:400")

    unit = machine.succeed("systemctl cat buzz-relay.service")
    t.assertIn("EnvironmentFile=/run/keys/buzz-relay.env", unit)
    t.assertIn("ProtectSystem=strict", unit)
    t.assertIn("MemoryDenyWriteExecute=true", unit)
    t.assertIn("CapabilityBoundingSet=", unit)
    t.assertIn("ReadWritePaths=/var/lib/buzz-relay/repos", unit)
    t.assertNotIn("https://push.buzz.xyz", unit)
    for secret in (
        "postgres://buzz@127.0.0.1:5432/buzz",
        "${ownerPrivateKey}",
        "${hookSecret}",
        "${s3AccessKey}",
        "${s3SecretKey}",
    ):
        t.assertNotIn(secret, unit)

    exec_start = machine.succeed("systemctl show buzz-relay.service -p ExecStart --value")
    t.assertIn("${package}/bin/buzz-relay", exec_start)
    pair_unit = machine.succeed("systemctl cat buzz-pair-relay.service")
    t.assertIn("DynamicUser=true", pair_unit)
    t.assertEqual(
        machine.succeed("systemctl show buzz-pair-relay.service -p StateDirectory --value").strip(),
        "",
    )

    machine.fail(
        "pid=$(systemctl show buzz-relay.service -p MainPID --value); "
        "nsenter -t $pid -m -- touch /etc/buzz-relay-sandbox-test"
    )
    machine.succeed("test ! -e /etc/buzz-relay-sandbox-test")
  '';
}
