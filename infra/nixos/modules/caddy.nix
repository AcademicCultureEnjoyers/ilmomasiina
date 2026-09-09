# NixOS module: TLS reverse proxy
#
# Fronts the app container on signup.academicculture.org. The security headers
# are carried over from the Caddyfile the Docker Compose deployment was using,
# so the migration does not silently relax them.
{ config, lib, ... }:

let
  domain = "signup.academicculture.org";
  appPort = config.services.ilmomasiina.port;
in
{
  services.caddy.enable = true;
  services.caddy.virtualHosts."${domain}".extraConfig = ''
    log {
      output stdout
      format json
    }

    encode gzip

    header {
      Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
      X-Content-Type-Options    "nosniff"
      X-Frame-Options           "DENY"
      Referrer-Policy           "no-referrer-when-downgrade"
    }

    reverse_proxy 127.0.0.1:${toString appPort} {
      flush_interval -1
    }

    handle_errors {
      header Content-Type "text/html; charset=utf-8"
      respond `${builtins.readFile ../../caddy/error-page.html}` {err.status_code}
    }
  '';

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
