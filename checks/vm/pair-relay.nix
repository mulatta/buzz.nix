# This test requires the real package: no sleeping or protocol fixture is used.
{
  pkgs,
  package,
  module ? ../../modules/buzz-pair-relay,
}:
pkgs.testers.runNixOSTest {
  name = "buzz-pair-relay-standalone";
  nodes.machine = {
    imports = [ module ];
    environment.systemPackages = [ pkgs.python3 ];
    services.buzz-pair-relay = {
      enable = true;
      inherit package;
    };
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("buzz-pair-relay.service")
    machine.wait_for_open_port(5000)
    machine.succeed("systemctl show buzz-pair-relay.service -p DynamicUser --value | grep -Fx yes")
    machine.succeed("systemctl show buzz-pair-relay.service -p ProtectSystem --value | grep -Fx strict")
    machine.succeed("systemctl cat buzz-pair-relay.service | grep -Fx 'CapabilityBoundingSet='")
    machine.fail("systemctl is-active buzz-relay.service")
    machine.fail("systemctl is-active postgresql.service")

    # Exercise an actual RFC 6455 upgrade against the packaged executable.
    # Path allowlisting is deliberately not asserted: it belongs to the proxy.
    machine.succeed(r"""python3 - <<'PY'
    import socket
    with socket.create_connection(("127.0.0.1", 5000), timeout=5) as connection:
        connection.sendall(
            b"GET /pair HTTP/1.1\r\n"
            b"Host: localhost:5000\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n"
            b"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
            b"Sec-WebSocket-Version: 13\r\n\r\n"
        )
        response = b""
        while b"\r\n\r\n" not in response:
            chunk = connection.recv(4096)
            assert chunk, response
            response += chunk
        assert response.split(b"\r\n", 1)[0] == b"HTTP/1.1 101 Switching Protocols", response
        assert b"s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" in response, response
    PY""")
  '';
}
