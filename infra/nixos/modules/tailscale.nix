{ config, lib, pkgs, ... }:

{
  # Enable the built-in Tailscale service
  services.tailscale.enable = true;

  # Explicitly use Tailscale's MagicDNS resolver so that tailnet hostnames
  # (e.g. "infra") resolve reliably. NixOS manages /etc/resolv.conf itself
  # and --accept-dns alone can be reverted by networkd on network events.
  networking.nameservers = [ "100.100.100.100" "1.1.1.1" ];

  # Open Tailscale UDP port in the firewall
  networking.firewall = {
    allowedUDPPorts = [ 41641 ];
    # Allow Tailscale-routed traffic
    trustedInterfaces = [ "tailscale0" ];
  };

  # One-shot unit that connects to Tailscale using the auth key
  systemd.services.tailscale-autoconnect = {
    description = "Tailscale automatic connection";
    after = [ "network-online.target" "tailscale.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Wait for tailscaled to become ready
      sleep 2

      # If already connected, do nothing
      status="$(${pkgs.tailscale}/bin/tailscale status --json | ${pkgs.jq}/bin/jq -r '.BackendState')"
      if [ "$status" = "Running" ]; then
        echo "Tailscale already connected"
        exit 0
      fi

      TAG="$(cat /etc/secrets/tailscale-tag 2>/dev/null || true)"
      TAG_ARG=""
      if [ -n "$TAG" ]; then TAG_ARG="--advertise-tags=$TAG"; fi

      ${pkgs.tailscale}/bin/tailscale up \
        --authkey "$(cat /etc/secrets/tailscale-authkey)" \
        --accept-routes \
        --accept-dns=true \
        $TAG_ARG
    '';
  };

  # Secret file: /etc/secrets/tailscale-authkey must exist (mode 0600, owned by root)
  # The file is deployed via nixos-anywhere --extra-files before activation.
  #
  # IMPORTANT: The auth key MUST be a reusable pre-auth key (created with
  # "Reusable: true" in the Tailscale admin console) for tagged server nodes.
}
