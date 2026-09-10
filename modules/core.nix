{ lib, pkgs, config, ... }:

# Hardware-agnostic system base: everything a desktop needs that is NOT
# drivers, filesystems or firmware. Every value is mkDefault so the
# importing config always wins.

let cfg = config.wasisabi; in
lib.mkIf cfg.enable {
  nix.settings = {
    experimental-features = lib.mkDefault [ "nix-command" "flakes" ];
    auto-optimise-store = lib.mkDefault true;
  };

  time.timeZone = lib.mkDefault cfg.timeZone;
  i18n.defaultLocale = lib.mkDefault cfg.locale;

  # Fonts: a monospace Noto fallback for CJK/emoji so nothing renders as tofu.
  fonts.packages = lib.mkDefault (with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-emoji
  ]);

  # Modern audio stack (PulseAudio API + ALSA + JACK compat).
  services.pipewire = lib.mkDefault {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Everything else a desktop session expects from the system.
  services = {
    gvfs.enable = lib.mkDefault true;     # trash/mounts for file managers
    upower.enable = lib.mkDefault true;    # battery reporting
    printing.enable = lib.mkDefault true;  # CUPS
  };

  # GPU accel + dconf for GTK settings + portals for Wayland desktop glue.
  hardware.graphics.enable = lib.mkDefault true;
  programs.dconf.enable = lib.mkDefault true;
  xdg.portal = lib.mkDefault {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  # Compressed-RAM swap: safe on any machine, no partition required.
  zramSwap.enable = lib.mkDefault cfg.zram.enable;

  # Small opinionated CLI base for any TTY session.
  environment.systemPackages = with pkgs; [
    git
    curl
    ripgrep
    fd
    btop
    tmux
  ];
}