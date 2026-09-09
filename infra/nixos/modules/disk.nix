# Disk partitioning layout for Hetzner cx23 (x86_64, BIOS boot, /dev/sda)
# Used by nixos-anywhere via disko.
{ ... }:

{
  disko.devices.disk.sda = {
    type    = "disk";
    device  = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        # BIOS boot partition required for GRUB on GPT disks
        boot = {
          size = "1M";
          type = "EF02";
          priority = 1;
        };
        root = {
          size    = "100%";
          content = {
            type       = "filesystem";
            format     = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
