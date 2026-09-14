{ lib, pkgs, config, ... }:

# Terminal + editors.

let cfg = config.wasisabi; in
lib.mkIf cfg.enable {
  programs.ghostty = lib.mkIf (cfg.terminal == "ghostty") {
    enable = true;
    settings = {
      font-family = "JetBrainsMono Nerd Font";
      font-size = 11;
      theme = "Catppuccin Mocha";      # bundled with ghostty; HM validates at build time
      background-opacity = 0.95;
      confirm-close-surface = false;
      copy-on-select = "clipboard";
    };
  };

  # kitty: GPU-accelerated like ghostty, but with a config format and a theme
  # ecosystem that predate it. Its themes ship as a separate package, so the
  # palette is set here explicitly rather than named.
  programs.kitty = lib.mkIf (cfg.terminal == "kitty") {
    enable = true;
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 11;
    };
    settings = {
      background_opacity = "0.95";
      confirm_os_window_close = 0;
      copy_on_select = "clipboard";
      # Catppuccin Mocha, matching ghostty's bundled theme and foot's colours
      # above, so switching terminals does not switch palettes.
      background = "#1e1e2e";
      foreground = "#cdd6f4";
      selection_background = "#585b70";
      selection_foreground = "#cdd6f4";
      cursor = "#f5e0dc";
      url_color = "#89b4fa";
    };
  };

  programs.foot = lib.mkIf (cfg.terminal == "foot") {
    enable = true;
    settings = {
      main = {
        font = "JetBrainsMono Nerd Font:size=11";
      };
      # foot 1.28 replaced the [colors] section with [colors-dark] and
      # [colors-light]. A stale [colors] is not ignored: foot refuses the
      # section and prints an error into your terminal on every launch.
      colors-dark = {
        background = "1e1e2e";
        foreground = "cdd6f4";
      };
    };
  };

  # Both editors ship; $EDITOR follows the option.
  programs.neovim = {
    enable = true;
    defaultEditor = cfg.editor == "neovim";
    withRuby = false;
    withPython3 = false;
    # Deliberately bare — users layer their config on top, or point the
    # flake at nixvim for a fully declarative config later.
  };

  programs.helix = {
    enable = true;
    defaultEditor = cfg.editor == "helix";
    settings = {
      theme = "catppuccin_mocha";      # bundled with helix
      editor.cursor-shape = {
        insert = "bar";
        normal = "block";
      };
    };
  };
}