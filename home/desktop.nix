{ lib, pkgs, config, ... }:

# The desktop session: Hyprland + Waybar + fuzzel + mako,
# with locking, idle, screenshots and recording wired up. Everything is a
# default the user can override file-by-file.

let
  cfg = config.wasisabi;

  # Catppuccin Mocha palette — single source of truth for the whole theme.
  c = rec {
    base = "1e1e2e";
    mantle = "181825";
    surface0 = "313244";
    surface1 = "45475a";
    text = "cdd6f4";
    subtext1 = "bac2de";
    mauve = "cba6f7";
    blue = "89b4fa";
    green = "a6e3a1";
    red = "f38ba8";
    peach = "fab387";
    overlay0 = "6c7086";
  };

  # Terminal command the binds refer to.
  termCmd =
    if cfg.terminal == "ghostty" then lib.getExe pkgs.ghostty
    else lib.getExe pkgs.foot;

  browserCmd =
    if cfg.browser == "firefox" then lib.getExe pkgs.firefox
    else if cfg.browser == "librewolf" then lib.getExe pkgs.librewolf
    else if cfg.browser == "chromium" then lib.getExe pkgs.chromium
    else lib.getExe pkgs.fuzzel;

  fileManagerCmd =
    if cfg.fileManager == "thunar" then lib.getExe pkgs.thunar
    else if cfg.fileManager == "nautilus" then lib.getExe pkgs.nautilus
    else termCmd;

  # Small scripts exposed as commands, so keybinds stay clean.
  screenshotScript = pkgs.writeShellApplication {
    name = "wasisabi-screenshot";
    runtimeInputs = [ pkgs.grim pkgs.slurp pkgs.wl-clipboard pkgs.libnotify ];
    text = ''
      grim -g "$(slurp)" - | wl-copy && notify-send "Screenshot" "Copied to clipboard"
    '';
  };

  recordScript = pkgs.writeShellApplication {
    name = "wasisabi-record";
    runtimeInputs = [ pkgs.wf-recorder pkgs.libnotify ];
    text = ''
      if pkill -INT wf-recorder 2>/dev/null; then
        notify-send "Recording" "Stopped"
      else
        mkdir -p "$HOME/Videos"
        wf-recorder -f "$HOME/Videos/recording-$(date +%s).mkv" &
        notify-send "Recording" "Started"
      fi
    '';
  };

  # Workspace binds, generated.
  wsBinds =
    builtins.concatLists (map (i: [
      "$mod, ${toString i}, workspace, ${toString i}"
      "$mod SHIFT, ${toString i}, movetoworkspace, ${toString i}"
    ]) [ 1 2 3 4 5 6 7 8 9 ]);

in
lib.mkIf cfg.enable {
  home.packages = [
    pkgs.waybar
    pkgs.fuzzel
    pkgs.mako
    pkgs.hyprlock
    pkgs.hypridle
    screenshotScript
    recordScript
  ];

  # ─── Hyprland compositor ───
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = true;
    configType = "hyprlang"; # pin the config syntax; HM master is migrating to lua
    settings = {
      # Primary modifier — from wasisabi.modKey (default SUPER; the demo VM
      # uses ALT because host desktops swallow Super combos before QEMU sees them).
      "$mod" = cfg.modKey;

      exec-once = [
        "waybar"
        "mako"
        "hypridle"
        "hyprpolkitagent"
        "blueman-applet"
      ];

      general = {
        gaps_in = 6;   # 0.56+: snake_case, not kebab
        gaps_out = 10;
        layout = "dwindle";
      };

      decoration = {
        rounding = 8;
        blur.enabled = false; # battery over eye candy
      };

      input.touchpad = {
        natural_scroll = true;
        tap-to-click = true; # ignored on machines without a touchpad
      };

      misc = {
        background_color = "rgb(${c.base})";
        disable_splash_rendering = true; # renamed from disable_splash in 0.56
      };

      bind = [
        # Launchers
        "$mod, Return, exec, ${termCmd}"
        "$mod, D, exec, ${lib.getExe pkgs.fuzzel}"
        "$mod, B, exec, ${browserCmd}"
        "$mod, E, exec, ${fileManagerCmd}"

        # Windows
        "$mod, Q, killactive"
        "$mod SHIFT, Q, exit"
        "$mod, Space, togglefloating"
        "$mod, F, fullscreen, 0"
        "$mod, Tab, cyclenext"
        "$mod SHIFT, Tab, cyclenext, prev"

        # Focus (vim keys)
        "$mod, H, movefocus, l"
        "$mod, J, movefocus, d"
        "$mod, K, movefocus, u"
        "$mod, L, movefocus, r"
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, J, movewindow, d"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, L, movewindow, r"

        # Screenshots / recording / lock
        "$mod SHIFT, S, exec, wasisabi-screenshot"
        "$mod SHIFT, R, exec, wasisabi-record"
        "$mod SHIFT, L, exec, ${lib.getExe pkgs.hyprlock}"
      ] ++ wsBinds;

      # Mouse
      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      # Media keys
      bindl = [
        ", XF86AudioPlay, exec, ${lib.getExe pkgs.playerctl} play-pause"
        ", XF86AudioNext, exec, ${lib.getExe pkgs.playerctl} next"
        ", XF86AudioPrev, exec, ${lib.getExe pkgs.playerctl} previous"
        ", XF86AudioMute, exec, ${lib.getExe pkgs.pamixer} -t"
        ", XF86AudioMicMute, exec, ${lib.getExe pkgs.pamixer} --default-source -t"
      ];

      # Repeatable keys (volume/brightness)
      bindel = [
        ", XF86AudioRaiseVolume, exec, ${lib.getExe pkgs.pamixer} -i 5"
        ", XF86AudioLowerVolume, exec, ${lib.getExe pkgs.pamixer} -d 5"
        ", XF86MonBrightnessUp, exec, ${lib.getExe pkgs.brightnessctl} set +5%"
        ", XF86MonBrightnessDown, exec, ${lib.getExe pkgs.brightnessctl} set 5%-"
      ];
    };
  };

  # ─── Waybar ───
  programs.waybar = {
    enable = true;
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 32;
      modules-left = [ "hyprland/workspaces" ];
      modules-center = [ "clock" ];
      modules-right = [
        "tray"
        "bluetooth"
        "network"
        "pulseaudio"
        "battery"
      ];
      "hyprland/workspaces".format = "{name}";
      clock.format = "{:%H:%M}";
      bluetooth.format = "  {status}";
      bluetooth.format-connected = " {num_connections}";
      network.format-wifi = "  {essid}";
      network.format-ethernet = "󰈀 {ipaddr}";
      network.format-disconnected = "󰖪 offline";
      pulseaudio.format = "{icon} {volume}%";
      pulseaudio.format-icons = {
        headphone = "🎧";
        default = [ "🔈" "🔉" "🔊" ];
      };
      battery.format = "{capacity}% {icon}";
      battery.format-icons = [ "" "" "" "" "" "" ];
      battery.states = {
        warning = 20;
        critical = 10;
      };
    };
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 13px;
        border: none;
        min-height: 0;
      }
      window#waybar {
        background: rgba(30, 30, 46, 0.9);
        color: #${c.text};
      }
      #workspaces button {
        padding: 0 8px;
        color: #${c.overlay0};
      }
      #workspaces button.active {
        color: #${c.mauve};
      }
      #battery.warning { color: #${c.peach}; }
      #battery.critical { color: #${c.red}; }
      #clock { font-weight: bold; color: #${c.blue}; }
      widget > * { padding: 0 6px; }
    '';
  };

  # ─── Notifications ───
  services.mako = {
    enable = true;
    settings = {
      anchor = "top-right";
      background-color = "#${c.base}EE";
      text-color = "#${c.text}";
      border-color = "#${c.blue}";
      border-radius = 8;
      border-size = 1;
      default-timeout = 4000;
    };
  };

  # ─── Launcher ───
  xdg.configFile."fuzzel/fuzzel.ini".text = ''
    [main]
    font=JetBrainsMono Nerd Font:size=11
    terminal=${lib.getExe pkgs.ghostty}
    layer=top
    [colors]
    background=${c.base}ee
    text=${c.text}ff
    match=${c.mauve}ff
    selection=${c.surface0}ff
    selection-text=${c.text}ff
    border=${c.blue}ff
  '';

  # ─── Lock screen ───
  xdg.configFile."hyprlock/hyprlock.conf".text = ''
    background {
      monitor =
      path = rgb(${c.base})
    }
    input-field {
      monitor =
      size = 300, 42
      outline thickness = 2
      outer_color = rgb(${c.surface0})
      inner_color = rgb(${c.surface1})
      font_color = rgb(${c.text})
    }
    label {
      monitor =
      text = Locked
      color = rgb(${c.subtext1})
      font_size = 24
      position = 0, 80
    }
  '';

  # ─── Idle: lock at 5min, screen off at 10, suspend at 15 ───
  xdg.configFile."hypridle/hypridle.conf".text = ''
    general {
      ignore_dbus_inhibit = false
    }
    listener {
      timeout = 300
      on-timeout = ${lib.getExe pkgs.hyprlock}
    }
    listener {
      timeout = 600
      on-timeout = hyprctl dispatch dpms off
      on-resume = hyprctl dispatch dpms on
    }
    listener {
      timeout = 900
      on-timeout = systemctl suspend
    }
  '';

  # ─── GTK theme ───
  gtk = {
    enable = true;
    theme = {
      name = "Catppuccin-Mocha-Standard-Mauve-Dark";
      package = pkgs.catppuccin-gtk;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    cursorTheme = {
      name = "Bibata-Modern-Ice";
      package = pkgs.bibata-cursors;
    };
  };
}