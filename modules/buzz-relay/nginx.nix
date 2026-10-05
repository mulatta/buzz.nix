{ config, lib, ... }:

let
  cfg = config.services.buzz-relay;
  inherit (cfg) nginx;
  # Restrict generated server names to plain DNS names, not nginx patterns or
  # authorities with ports. Custom listeners belong in a hand-written vhost.
  hostPattern = "[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?";
  validHost = value: value != null && builtins.match hostPattern value != null;
  # DNS names are case-insensitive; use the same canonical form for collision
  # checks, nginx server names, and generated public URLs.
  host = if nginx.hostName == null then "invalid.example" else lib.toLower nginx.hostName;
  adminHost = if cfg.adminHost == null then null else lib.toLower cfg.adminHost;
  httpScheme = if nginx.forceSSL then "https" else "http";
  wsScheme = if nginx.forceSSL then "wss" else "ws";
  pairingMatch =
    if cfg.pairingRelay.url == null then
      null
    else
      builtins.match "${wsScheme}://(${hostPattern})/pair" cfg.pairingRelay.url;
  pairingHost = if pairingMatch == null then null else lib.toLower (builtins.head pairingMatch);
  upstreamHost =
    address:
    if address == "0.0.0.0" then
      "127.0.0.1"
    else if address == "::" then
      "[::1]"
    else if lib.hasInfix ":" address && !(lib.hasPrefix "[" address) then
      "[${address}]"
    else
      address;
  proxy = address: port: {
    inherit (nginx) enableACME forceSSL;
    locations."/" = {
      proxyPass = "http://${upstreamHost address}:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = ''
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
      '';
    };
    # Git packs default to 500 MiB. Leave room for HTTP multipart overhead.
    extraConfig = "client_max_body_size ${
      toString (lib.max (512 * 1024 * 1024) (cfg.git.maxPackBytes + 1024 * 1024))
    };";
  };
  relayProxy = proxy cfg.listenAddress cfg.port;
  pairCfg = config.services.buzz-pair-relay;
  pairLocation = (proxy pairCfg.listenAddress pairCfg.port).locations."/" // {
    extraConfig = ''
      proxy_read_timeout 130s;
      proxy_send_timeout 130s;
      proxy_buffering off;
    '';
  };
  localPair = cfg.pairingRelay.enable && pairingHost != null;
  withPair =
    name: base:
    base
    // {
      locations =
        base.locations
        // lib.optionalAttrs (localPair && pairingHost == name) {
          "= /pair" = pairLocation;
        };
    };
in
{
  options.services.buzz-relay.nginx = {
    enable = lib.mkEnableOption "nginx reverse proxy for Buzz relay";
    hostName = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      example = "buzz.example.org";
      description = "Public DNS name, without a scheme, port, or path. Required when nginx integration is enabled.";
    };
    enableACME = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Request ACME certificates for generated virtual hosts. Configure security.acme separately.";
    };
    forceSSL = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Redirect HTTP to HTTPS. Public URL defaults use HTTPS/WSS when true,
        and HTTP/WS otherwise. If ACME is disabled, configure TLS certificates
        on the generated nginx virtual hosts separately.
      '';
    };
  };

  config = lib.mkIf nginx.enable {
    assertions = [
      {
        assertion = cfg.enable;
        message = "services.buzz-relay.nginx.enable requires services.buzz-relay.enable.";
      }
      {
        assertion = validHost nginx.hostName;
        message = "services.buzz-relay.nginx.hostName must be a plain DNS name without a scheme, port, path, or nginx wildcard.";
      }
      {
        assertion = !cfg.pairingRelay.enable || pairingMatch != null;
        message = "With nginx enabled, services.buzz-relay.pairingRelay.url must be a ${wsScheme}:// DNS URL with exactly /pair and without a port, query, or fragment.";
      }
      {
        assertion = !cfg.pairingRelay.enable || pairCfg.enable;
        message = "services.buzz-relay.pairingRelay.enable requires services.buzz-pair-relay.enable.";
      }
      {
        assertion = cfg.adminHost == null || validHost cfg.adminHost;
        message = "With nginx enabled, services.buzz-relay.adminHost must be a plain DNS name without a port; custom authority routing needs a hand-written nginx configuration.";
      }
    ];

    services.buzz-relay = {
      pairingRelay.url = lib.mkIf cfg.pairingRelay.enable (lib.mkDefault "${wsScheme}://${host}/pair");
      relayUrl = lib.mkDefault "${wsScheme}://${host}";
      media.baseUrl = lib.mkDefault "${httpScheme}://${host}/media";
      corsOrigins = lib.mkDefault (
        [ "${httpScheme}://${host}" ]
        ++ lib.optional (adminHost != null && adminHost != host) "${httpScheme}://${adminHost}"
      );
    };

    # Only the application and explicitly enabled pairing listener are proxied.
    # Health and metrics listeners remain private. Firewall and ACME account
    # policy remain under the administrator's control.
    services.nginx = {
      enable = true;
      virtualHosts = {
        ${host} = withPair host relayProxy;
      }
      // lib.optionalAttrs (adminHost != null && adminHost != host && validHost cfg.adminHost) {
        ${adminHost} = withPair adminHost relayProxy;
      }
      //
        lib.optionalAttrs
          (cfg.pairingRelay.enable && pairingHost != null && pairingHost != host && pairingHost != adminHost)
          {
            ${pairingHost} = {
              inherit (nginx) enableACME forceSSL;
              locations = {
                "= /pair" = pairLocation;
                "/".return = "404";
              };
            };
          };
    };
  };
}
