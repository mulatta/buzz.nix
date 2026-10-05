{
  lib,
  module,
  package,
  pkgs,
}:

let
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

      printf %s 'postgres://buzz@127.0.0.1:5432/buzz' > /run/keys/DATABASE_URL
      printf %s 'redis://127.0.0.1:6379' > /run/keys/REDIS_URL
      printf %s '${ownerPrivateKey}' > /run/keys/BUZZ_RELAY_PRIVATE_KEY
      printf %s '${hookSecret}' > /run/keys/BUZZ_GIT_HOOK_HMAC_SECRET
      printf %s '${s3AccessKey}' > /run/keys/BUZZ_S3_ACCESS_KEY
      printf %s '${s3SecretKey}' > /run/keys/BUZZ_S3_SECRET_KEY

      chmod 0400 /run/keys/rustfs.env /run/keys/{DATABASE_URL,REDIS_URL,BUZZ_RELAY_PRIVATE_KEY,BUZZ_GIT_HOOK_HMAC_SECRET,BUZZ_S3_ACCESS_KEY,BUZZ_S3_SECRET_KEY}
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
            endpoint_url="http://127.0.0.1:9002",
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
        written = client.put_object(Bucket="${bucket}", Key=key, Body=payload)
        result = client.get_object(Bucket="${bucket}", Key=key)
        try:
            received = result["Body"].read()
        finally:
            result["Body"].close()
        if received != payload:
            raise RuntimeError(f"S3 roundtrip mismatch: {received!r}")
        try:
            client.put_object(
                Bucket="${bucket}", Key=key, Body=b"must-not-be-written",
                IfMatch=written["ETag"],
            )
        except ClientError as error:
            metadata = error.response["ResponseMetadata"]
            assert metadata["HTTPStatusCode"] == 503, error
            assert metadata["HTTPHeaders"]["x-buzz-test-fault"] == "if-match"
        else:
            raise RuntimeError("Conditional fault injection did not fire")
        result = client.get_object(Bucket="${bucket}", Key=key)
        try:
            assert result["Body"].read() == payload
        finally:
            result["Body"].close()
        client.delete_object(Bucket="${bucket}", Key=key)
        print("RustFS CRUD through proxy passed; deliberate If-Match 503 verified")
      '';
  s3ProbeExe = toString s3Probe;
in
pkgs.testers.runNixOSTest {
  name = "buzz-relay-s3-admission-gate";
  meta.timeout = 240;

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
        environmentFile = "/run/keys/rustfs.env";
        settings = {
          RUSTFS_VOLUMES = "/var/lib/rustfs";
          RUSTFS_ADDRESS = "127.0.0.1:9000";
          RUSTFS_CONSOLE_ADDRESS = "127.0.0.1:9001";
        };
      };

      # Keep the real backend unpatched. Only conditional updates fail, so
      # admission must reject an unhealthy CAS path even while CRUD works.
      services.nginx = {
        enable = true;
        # Define the format before the virtual host's access_log uses it.
        commonHttpConfig = ''
          log_format s3_fault '$status $request_method $uri $sent_http_x_buzz_test_fault';
        '';
        virtualHosts.s3-fault = {
          listen = [
            {
              addr = "127.0.0.1";
              port = 9002;
            }
          ];
          extraConfig = ''
            access_log /var/log/nginx/s3-fault.log s3_fault;
          '';
          locations."/" = {
            proxyPass = "http://127.0.0.1:9000";
            extraConfig = ''
              # Both test clients sign this fixed endpoint authority. Preserve
              # its port for SigV4 without trusting a caller-controlled Host.
              proxy_set_header Host 127.0.0.1:9002;
              if ($http_if_match != "") {
                add_header X-Buzz-Test-Fault if-match always;
                return 503 "buzz-test deliberate If-Match failure";
              }
            '';
          };
        };
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
        secretFiles = {
          DATABASE_URL = "/run/keys/DATABASE_URL";
          REDIS_URL = "/run/keys/REDIS_URL";
          BUZZ_RELAY_PRIVATE_KEY = "/run/keys/BUZZ_RELAY_PRIVATE_KEY";
          BUZZ_GIT_HOOK_HMAC_SECRET = "/run/keys/BUZZ_GIT_HOOK_HMAC_SECRET";
          BUZZ_S3_ACCESS_KEY = "/run/keys/BUZZ_S3_ACCESS_KEY";
          BUZZ_S3_SECRET_KEY = "/run/keys/BUZZ_S3_SECRET_KEY";
        };
        environment.BUZZ_GIT_CONFORMANCE_PROBE = "true";
        media = {
          baseUrl = "http://relay.test:3000/media";
          s3Endpoint = "http://127.0.0.1:9002";
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
          "nginx.service"
        ];
        after = [
          "buzz-test-secrets.service"
          "rustfs.service"
          "nginx.service"
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

        # Keep the single failed admission attempt observable.
        serviceConfig.Restart = lib.mkForce "no";
      };
    };

  testScript = ''
    import re
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
    machine.wait_for_unit("nginx.service")
    machine.wait_for_open_port(9002)
    machine.wait_for_unit("rustfs-bucket.service")
    machine.wait_for_unit("buzz-pair-relay.service")
    machine.wait_for_open_port(5000)
    machine.wait_until_succeeds("systemctl is-failed --quiet buzz-relay.service", timeout=120)

    t.assertEqual(
        machine.succeed("systemctl show buzz-relay.service -p Result --value").strip(),
        "exit-code",
    )
    t.assertEqual(
        machine.succeed("systemctl show buzz-relay.service -p ExecMainStatus --value").strip(),
        "1",
    )
    t.assertEqual(
        machine.succeed("systemctl show buzz-relay.service -p NRestarts --value").strip(),
        "0",
    )

    journal = machine.succeed("journalctl -u buzz-relay.service -b --no-pager -o cat")
    t.assertIn("Database migrations complete", journal)
    t.assertIn("Relay owner bootstrapped", journal)
    t.assertIn("running git object-store conformance probe (A3 gate)", journal)
    t.assertIn("git conformance probe failed", journal)
    t.assertIn("conformance probe failed in phase 'if_match_race'", journal)
    t.assertIn("Got HTTP 503", journal)
    t.assertNotIn("git object-store backend admitted", journal)

    # Separate the relay's injected failures from the bootstrap probe's key.
    machine.wait_until_succeeds(
        "grep -E '^503 PUT /${bucket}/probe/pointer-[^ ]+ if-match$' "
        "/var/log/nginx/s3-fault.log"
    )
    bootstrap_journal = machine.succeed(
        "journalctl -u rustfs-bucket.service -b --no-pager -o cat"
    )
    t.assertIn("RustFS CRUD through proxy passed; deliberate If-Match 503 verified", bootstrap_journal)

    for port in (3000, 8080, 9102):
        machine.fail(f"curl --fail --silent --max-time 1 http://127.0.0.1:{port}/")

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

    machine.succeed("systemctl is-active --quiet postgresql.service")
    machine.succeed("systemctl is-active --quiet redis-buzz.service")
    machine.succeed("systemctl is-active --quiet rustfs.service")
    machine.succeed("systemctl is-active --quiet buzz-pair-relay.service")
    machine.succeed("${s3ProbeExe}")

    for path in (
        "/var/lib/buzz-relay",
        "/var/lib/buzz-relay/repos",
        "/var/cache/buzz-relay",
        "/var/cache/buzz-relay/git-pack-cache",
    ):
        machine.succeed(f"test $(stat -c %U:%G:%a {path}) = buzz-relay:buzz-relay:700")
    machine.succeed("test $(stat -c %U:%G:%a /run/keys/DATABASE_URL) = root:root:400")
    machine.succeed("test $(stat -c %U:%G:%a /run/keys/rustfs.env) = root:root:400")

    unit = machine.succeed("systemctl cat buzz-relay.service")
    t.assertIn("LoadCredential=DATABASE_URL:/run/keys/DATABASE_URL", unit)
    t.assertNotIn("EnvironmentFile=", unit)
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
    # ExecStart names the credential-loading wrapper, not its final exec.
    wrapper_match = re.search(r"path=([^ ;}]+)", exec_start)
    assert wrapper_match is not None, exec_start
    wrapper = machine.succeed("cat " + shlex.quote(wrapper_match.group(1)))
    t.assertIn("exec ${package}/bin/buzz-relay", wrapper)
    pair_unit = machine.succeed("systemctl cat buzz-pair-relay.service")
    t.assertIn("DynamicUser=true", pair_unit)
    t.assertEqual(
        machine.succeed("systemctl show buzz-pair-relay.service -p StateDirectory --value").strip(),
        "",
    )
  '';
}
