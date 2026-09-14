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

  # Fonts: the nerd font the home layer names (ghostty, foot, waybar all ask
  # for "JetBrainsMono Nerd Font"), plus a Noto fallback for CJK/emoji so
  # nothing renders as tofu.
  #
  # NOT mkDefault, and that is the whole point of this comment. nixpkgs
  # defines its own base font list (dejavu, liberation, noto, gyre, ...) at
  # NORMAL priority, and `fonts.packages` is a list: a normal-priority
  # definition does not merge with a mkDefault one, it DISCARDS it. So with
  # mkDefault here the nerd font silently never got installed, fontconfig
  # substituted DejaVu Sans, and terminals rendered a PROPORTIONAL font --
  # visibly ragged, with foot warning "font does not appear to be monospace"
  # on every launch. The demo VM had it too.
  #
  # Declared at normal priority these MERGE with the nixpkgs list, which is
  # what a list option should do. A consumer who genuinely wants to drop them
  # still can, with mkForce.
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];

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

  # Portals: the compositor module (programs.niri) already adds the gnome
  # portal and the interface routing it wants. We only add the GTK portal,
  # which is the generic fallback for file chooser, print and settings.
  # Assign per-leaf rather than wrapping the namespace in one mkDefault:
  # extraPortals is a list, so this merges with the compositor's instead of
  # racing it.
  xdg.portal.enable = lib.mkDefault true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

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