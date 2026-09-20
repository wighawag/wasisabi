# A stand-in for the hardware-configuration.nix that nixos-generate-config
# writes on a real target, used only so the emit-roundtrip check can evaluate
# the generated flake as a real NixOS configuration. It is not installed
# anywhere and it describes no actual machine.

{ lib, ... }:

{
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/0000-0000";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  # Deliberately NO bootloader settings, because the real
  # hardware-configuration.nix does not have any either: nixos-generate-config
  # puts those in the configuration.nix that the installer throws away. Having
  # them here once hid a missing bootloader from every check, and the first
  # thing to notice was a VM install failing at the very last step.
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
