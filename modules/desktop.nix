{ lib, pkgs, config, ... }:

# The session: niri compositor, greetd login, Wayland CLI tools.
# User-facing apps and dotfiles live in the home-manager layer (../home).

let cfg = config.wasisabi; in
lib.mkIf cfg.enable {
  # niri — a scrollable-tiling compositor. The nixpkgs module does the
  # session wiring for us: the session package for display managers, the
  # systemd user units used by `niri-session`, gnome-keyring for the Secret
  # portal, and the portal config (niri prefers gnome + gtk; the gnome one
  # is what makes screencasting work).
  programs.niri = {
    enable = lib.mkDefault true;

    # The gnome portal uses Nautilus as its file chooser. We default to
    # Thunar, so route FileChooser at the GTK portal instead. Users who set
    # `wasisabi.fileManager = "nautilus"` can flip this back on.
    useNautilus = lib.mkDefault false;
  };

  security.polkit.enable = lib.mkDefault true;

  # swaylock authenticates through PAM. Without this service entry it can
  # take a password but never accept it, which locks you out of your own
  # session until you switch to a TTY.
  security.pam.services.swaylock = { };

  # tuigreet's --remember/--remember-session persist state in
  # $HOME/.cache/tuigreet. The greetd module creates the greeter user
  # without a home directory, which makes tuigreet crash on startup
  # (black screen with a blinking cursor). Give it a writable home.
  users.users.greeter = lib.mkIf cfg.greetd.enable {
    home = lib.mkDefault "/var/lib/greeter";
    createHome = lib.mkDefault true;
  };

  services.greetd = lib.mkIf cfg.greetd.enable {
    enable = lib.mkDefault true;
    useTextGreeter = lib.mkDefault true;
    settings.default_session = {
      # NOTE: assign sub-options directly with per-leaf mkDefault — wrapping
      # the whole namespace in one mkDefault gets silently dropped by the
      # module system when it crosses into the TOML-typed `settings` option.
      #
      # niri-session (rather than plain niri) is what imports the session
      # environment into the systemd user manager and D-Bus. Skip it and
      # portals, screencasting and every user service break in confusing ways.
      #
      # It runs on the VT, so anything it prints lands on your screen between
      # the password prompt and the first frame of the desktop. Upstream's
      # script currently calls `systemctl --user import-environment` with no
      # argument list, which systemd warns about. systemd-cat sends that to
      # the journal instead of the console: still diagnosable with
      # `journalctl -t niri-session`, no longer visible mid-login.
      command = lib.mkDefault "${lib.getExe pkgs.tuigreet} --time --remember --remember-session --cmd '${lib.getExe' pkgs.systemd "systemd-cat"} --identifier=niri-session ${lib.getExe' pkgs.niri "niri-session"}'";
      user = lib.mkDefault "greeter";
    };
  };

  # Session-adjacent CLI tools. GUI apps (bar, launcher, terminal, ...)
  # are managed by the home layer so users can swap them per-account.
  #
  # niri has a built-in screenshot UI, but grim/slurp stay: they are what
  # other tools shell out to, and niri implements wlr-screencopy v3 so they
  # work unmodified.
  environment.systemPackages = with pkgs; [
    grim            # screenshots
    slurp           # region picker
    wl-clipboard    # clipboard
    brightnessctl
    pamixer
    playerctl
    wf-recorder
  ];
}
