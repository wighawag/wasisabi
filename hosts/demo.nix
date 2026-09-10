{ lib, pkgs, ... }:

# A demo machine — deliberately NOT real hardware. It exists so that
#   nix flake check                      → validates the whole layer evals
#   nixos-rebuild build-vm --flake .#demo → boots the desktop in QEMU
# and proves the module layers are hardware-agnostic.

{
  # Fake disk identity — only used when building the VM.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  users.users.demo = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" ];
    password = "demo";  # declarative (not initialPassword) — always works
  };

  # Debug aid: dump greetd + home-manager diagnostics to the serial console on boot.
  systemd.services.debug-greetd = {
    wantedBy = [ "multi-user.target" ];
    after = [ "greetd.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      sleep 15
      {
        echo "=== greetd state ==="
        systemctl is-active greetd || true
        echo "=== tuigreet processes ==="
        ${pkgs.procps}/bin/ps aux | grep -v grep | grep tuigreet || echo "NO TUIGREET RUNNING"
        echo "=== greetd journal ==="
        journalctl -u greetd --no-pager -n 15 || true
        echo "=== home-manager-demo status ==="
        systemctl status home-manager-demo.service -l --no-pager || true
        echo "=== home-manager-demo journal ==="
        journalctl -u home-manager-demo.service --no-pager -n 40 || true
      } > /dev/ttyS0 2>&1 || true
    '';
  };

  # Enable the system layer (the home layer is wired in flake.nix).
  wasisabi.enable = true;

  # Debug/testing access for the demo VM.
  virtualisation.vmVariant = {
    services.openssh.enable = true;
    virtualisation.forwardPorts = [{
      from = "host";
      host.port = 2222;
      guest.port = 22;
    }];
  };

  system.stateVersion = "26.05";
}