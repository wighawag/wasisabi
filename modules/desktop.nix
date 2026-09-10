{ lib, pkgs, config, ... }:

# The session: Hyprland compositor, greetd login, Wayland CLI tools.
# User-facing apps and dotfiles live in the home-manager layer (../home).

let cfg = config.wasisabi; in
lib.mkIf cfg.enable {
  programs.hyprland = {
    enable = lib.mkDefault true;
    xwayland.enable = lib.mkDefault true;
  };

  security.polkit.enable = lib.mkDefault true;

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
      command = lib.mkDefault "${lib.getExe pkgs.tuigreet} --time --remember --remember-session --cmd ${lib.getExe' pkgs.hyprland "start-hyprland"}";
      user = lib.mkDefault "greeter";
    };
  };

  # Session-adjacent CLI tools. GUI apps (bar, launcher, terminal, ...)
  # are managed by the home layer so users can swap them per-account.
  environment.systemPackages = with pkgs; [
    grim            # screenshots
    slurp           # region picker
    wl-clipboard    # clipboard
    brightnessctl
    pamixer
    playerctl
    wf-recorder
    hyprpolkitagent
  ];
}