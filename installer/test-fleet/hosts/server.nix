# The fleet's other host. Never installed by the test; it only has to exist
# and evaluate.
{
  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };
  boot.loader.grub.device = "/dev/sda";
  networking.hostName = "server";
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.11";
}
