{ lib, config, ... }:

# Connectivity. Deliberately includes WWAN (LTE modems) and Bluetooth:
# both are harmless when the hardware is absent, which keeps this layer
# hardware-agnostic.

let cfg = config.wasisabi; in
lib.mkIf cfg.enable {
  networking.networkmanager.enable = lib.mkDefault true;
  networking.firewall.enable = lib.mkDefault true;

  hardware.bluetooth = lib.mkIf cfg.bluetooth.enable (lib.mkDefault {
    enable = true;
    powerOnBoot = true;
  });

  services.blueman.enable = lib.mkIf cfg.bluetooth.enable (lib.mkDefault true);

  networking.modemmanager.enable = lib.mkIf cfg.cellular.enable (lib.mkDefault true);
}