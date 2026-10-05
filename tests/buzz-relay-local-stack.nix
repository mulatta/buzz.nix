{
  pkgs,
  module,
  pairPackage,
}:
let
  fixture = pkgs.writeShellApplication {
    name = "buzz-relay";
    runtimeInputs = [
      pkgs.python3
      pkgs.postgresql
      pkgs.redis
    ];
    text = ''
      psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'CREATE TABLE IF NOT EXISTS wiring_check (id integer);'
      redis-cli -u "$REDIS_URL" SET buzz-wiring ready
      exec python3 -m http.server 3000 --bind 127.0.0.1
    '';
  };
in
pkgs.testers.runNixOSTest {
  name = "buzz-relay-local-stack";
  nodes.machine = {
    imports = [ module ];
    environment.systemPackages = [
      pkgs.postgresql
      pkgs.redis
      pkgs.curl
      pkgs.python3
    ];
    systemd.tmpfiles.rules = [
      "d /run/secrets 0700 root root -"
      "f /run/secrets/key 0600 root root - fixture-key"
      "f /run/secrets/access 0600 root root - fixture-access"
      "f /run/secrets/secret 0600 root root - fixture-secret"
    ];
    services.buzz-pair-relay.package = pairPackage;
    services.buzz-relay = {
      enable = true;
      package = fixture;
      ownerPubkey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
      pairingRelay.enable = true;
      database.createLocally = true;
      redis.createLocally = true;
      nginx = {
        enable = true;
        hostName = "buzz.test";
        enableACME = false;
        forceSSL = false;
      };
      media.s3Endpoint = "https://s3.example";
      secretFiles = {
        BUZZ_RELAY_PRIVATE_KEY = "/run/secrets/key";
        BUZZ_S3_ACCESS_KEY = "/run/secrets/access";
        BUZZ_S3_SECRET_KEY = "/run/secrets/secret";
      };
    };
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("buzz-relay.service")
    machine.wait_for_unit("nginx.service")
    machine.wait_for_unit("buzz-pair-relay.service")
    machine.wait_for_open_port(3000)
    machine.succeed("curl --fail -H 'Host: buzz.test' http://127.0.0.1/")
    machine.succeed("sudo -u buzz-relay psql -d buzz-relay -c 'SELECT * FROM wiring_check'")
    machine.succeed("redis-cli -p 6380 GET buzz-wiring | grep -Fx ready")
    machine.succeed("systemctl show buzz-relay.service -p Requires --value | grep postgresql-setup.service")
    machine.succeed(r"""python3 - <<'PY'
    import socket
    for path, expected in [("/pair", 101), ("/pair/", 404), ("/pair/extra", 404)]:
        with socket.create_connection(("127.0.0.1", 80), timeout=5) as connection:
            request = (
                f"GET {path} HTTP/1.1\r\nHost: buzz.test\r\n"
                "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
                "Sec-WebSocket-Version: 13\r\n\r\n"
            )
            connection.sendall(request.encode())
            response = b""
            while b"\r\n\r\n" not in response:
                chunk = connection.recv(4096)
                assert chunk, response
                response += chunk
            assert int(response.split(b" ")[1]) == expected, (path, response)
    PY""")
  '';
}
