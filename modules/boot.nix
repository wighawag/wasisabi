{ lib, pkgs, config, ... }:

# Boot presentation. Nothing here changes what boots, only what you see while
# it does: a themed splash instead of a wall of unit status lines.
#
# The handoff needs no wiring from us: the nixpkgs greetd module aliases
# itself to display-manager.service and orders itself after
# plymouth-quit-wait.service, so the splash hands straight over to tuigreet.

let
  cfg = config.wasisabi;

  # catppuccin-plymouth defaults to the macchiato flavour; the rest of
  # wasi-sabi is Mocha.
  plymouthTheme = pkgs.catppuccin-plymouth.override { variant = "mocha"; };
in
lib.mkIf (cfg.enable && cfg.splash.enable) {
  boot.plymouth = {
    enable = lib.mkDefault true;
    themePackages = lib.mkDefault [ plymouthTheme ];
    theme = lib.mkDefault "catppuccin-mocha";
  };

  # Quiet the console so the splash is not fighting kernel and unit output.
  #
  # Note what `quiet` does NOT hide: systemd password prompts (disk unlock),
  # the emergency shell, and fsck errors that need an answer. A boot that
  # actually fails is still visible and still interactive. Set
  # `wasisabi.splash.enable = false` if you would rather watch every unit.
  #
  # kernelParams is an additive list, so these are appended rather than
  # mkDefault'd: a user adding their own params keeps these too.
  boot.kernelParams = [
    "quiet"                          # kernel messages
    "splash"
    "loglevel=3"
    "systemd.show_status=false"      # the [ OK ] unit lines in stage 2
    "rd.systemd.show_status=false"   # ... and in the initrd
    "rd.udev.log_level=3"
    "udev.log_level=3"
  ];

  boot.initrd.verbose = lib.mkDefault false;
  boot.consoleLogLevel = lib.mkDefault 0;
}
