# Hardware configuration for Hetzner cx23 (QEMU/KVM guest, x86_64)
# Disk layout is managed by modules/disk.nix via disko.
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sd_mod" ];
  boot.initrd.kernelModules          = [];
  boot.kernelModules                 = [];
  boot.extraModulePackages           = [];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
