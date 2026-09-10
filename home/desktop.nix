{ lib, pkgs, config, ... }:

# The desktop session: niri + Waybar + fuzzel + mako, with locking, idle,
# screenshots and recording wired up. Everything is a default the user can
# override file-by-file.
#
# niri is a scrollable-tiling compositor: windows live in columns on an
# infinite horizontal strip, and opening a window never resizes the ones
# already open. See notes/compositor-alternatives.md for why it is the
# default and what the alternatives would cost.

let
  cfg = config.wasisabi;

  # Catppuccin Mocha palette — single source of truth for the whole theme.
  # Deliberately compositor-independent: it themes the bar, launcher,
  # notifications, lock screen and GTK, none of which know what compositor
  # they are running under.
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

  # niri names the primary modifier once, and every bind then says "Mod".
  # That is why the binds below never interpolate the mod key.
  niriModKey = {
    SUPER = "Super";
    ALT = "Alt";
    CTRL = "Ctrl";
  }.${cfg.modKey};

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

  lockCmd = "${lib.getExe pkgs.swaylock} -f";

  # Screen recording as a command, so the keybind stays clean. Screenshots
  # need no script: niri has a built-in screenshot UI that saves to
  # screenshot-path and copies to the clipboard in one action.
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

  # Workspace binds, generated. niri workspaces are dynamic, so an index
  # beyond the current count lands on the bottom-most empty workspace.
  wsBinds = lib.listToAttrs (lib.concatMap (i: [
    (lib.nameValuePair "Mod+${toString i}" { focus-workspace = i; })
    (lib.nameValuePair "Mod+Shift+${toString i}" { move-column-to-workspace = i; })
  ]) (lib.range 1 9));

in
lib.mkIf cfg.enable {
  home.packages = [
    pkgs.fuzzel
    recordScript
  ];

  # ─── niri compositor ───
  wayland.windowManager.niri = {
    enable = true;

    # Runs `niri validate` on the generated KDL as part of the build, so a
    # broken option fails `nixos-rebuild` instead of dropping you into a
    # black screen. This is the main reason niri is the default.
    checkConfig = true;

    settings = {
      input = {
        # Empty xkb block: niri reads the layout from systemd-localed, so
        # `localectl set-x11-keymap` is the single place to set it.
        keyboard.xkb = { };
        touchpad = {
          tap = { };
          natural-scroll = { };
        };
        # Primary modifier — from wasisabi.modKey (default SUPER; the demo
        # VM uses ALT because host desktops swallow Super combos before
        # QEMU sees them).
        mod-key = niriModKey;
      };

      layout = {
        gaps = 8;
        center-focused-column = "never";
        default-column-width.proportion = 0.5;
        background-color = "#${c.base}";
        focus-ring = {
          width = 2;
          active-color = "#${c.mauve}";
          inactive-color = "#${c.surface1}";
        };
      };

      # Without this niri logs "error loading xcursor default@24: no default
      # icon" and falls back to a built-in cursor. It has to match
      # home.pointerCursor below.
      cursor = {
        xcursor-theme = "Bibata-Modern-Ice";
        xcursor-size = 24;
      };

      # Ask clients to drop their own title bars so niri can draw the focus
      # ring around the window rather than behind it.
      prefer-no-csd = { };

      screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";

      # The hotkey cheat sheet is genuinely useful, but not on every login.
      # Mod+Shift+Slash brings it up on demand.
      hotkey-overlay.skip-at-startup = { };

      binds = {
        # Launchers
        "Mod+Return".spawn = termCmd;
        "Mod+D".spawn = lib.getExe pkgs.fuzzel;
        "Mod+B".spawn = browserCmd;
        "Mod+E".spawn = fileManagerCmd;

        # Windows
        "Mod+Q" = { _props.repeat = false; close-window = { }; };
        "Mod+Shift+Q".quit = { };  # shows a confirmation dialog
        "Mod+Space".toggle-window-floating = { };
        "Mod+F".fullscreen-window = { };
        "Mod+Shift+F".maximize-column = { };
        "Mod+C".center-column = { };
        "Mod+O" = { _props.repeat = false; toggle-overview = { }; };
        "Mod+Shift+Slash".show-hotkey-overlay = { };

        # Focus (vim keys + arrows). In a scrollable layout, left/right move
        # between columns and up/down move within a column.
        "Mod+H".focus-column-left = { };
        "Mod+J".focus-window-down = { };
        "Mod+K".focus-window-up = { };
        "Mod+L".focus-column-right = { };
        "Mod+Left".focus-column-left = { };
        "Mod+Down".focus-window-down = { };
        "Mod+Up".focus-window-up = { };
        "Mod+Right".focus-column-right = { };

        # Move. Ctrl rather than Shift, because Mod+Shift+L is the lock
        # bind: niri's own defaults use Ctrl here for the same reason.
        "Mod+Ctrl+H".move-column-left = { };
        "Mod+Ctrl+J".move-window-down = { };
        "Mod+Ctrl+K".move-window-up = { };
        "Mod+Ctrl+L".move-column-right = { };

        # Column shaping — the part that has no equivalent in a classic tiler.
        "Mod+R".switch-preset-column-width = { };
        "Mod+Minus".set-column-width = "-10%";
        "Mod+Equal".set-column-width = "+10%";
        "Mod+BracketLeft".consume-or-expel-window-left = { };
        "Mod+BracketRight".consume-or-expel-window-right = { };
        "Mod+W".toggle-column-tabbed-display = { };

        # Workspaces (vertical), beyond the numbered binds below.
        "Mod+U".focus-workspace-down = { };
        "Mod+I".focus-workspace-up = { };

        # Screenshots: built-in, interactive, saves to disk and clipboard.
        "Mod+Shift+S".screenshot = { };
        "Print".screenshot-screen = { };
        "Alt+Print".screenshot-window = { };

        # Recording / lock / monitors off
        "Mod+Shift+R".spawn = lib.getExe recordScript;
        "Mod+Shift+L".spawn-sh = lockCmd;
        "Mod+Shift+P".power-off-monitors = { };

        # Escape hatch for apps that grab the keyboard (remote desktop, KVM).
        "Mod+Escape" = {
          _props.allow-inhibiting = false;
          toggle-keyboard-shortcuts-inhibit = { };
        };

        # Media keys — allow-when-locked so they work on the lock screen.
        "XF86AudioPlay" = { _props.allow-when-locked = true; spawn = [ (lib.getExe pkgs.playerctl) "play-pause" ]; };
        "XF86AudioNext" = { _props.allow-when-locked = true; spawn = [ (lib.getExe pkgs.playerctl) "next" ]; };
        "XF86AudioPrev" = { _props.allow-when-locked = true; spawn = [ (lib.getExe pkgs.playerctl) "previous" ]; };
        "XF86AudioMute" = { _props.allow-when-locked = true; spawn = [ (lib.getExe pkgs.pamixer) "-t" ]; };
        "XF86AudioMicMute" = { _props.allow-when-locked = true; spawn = [ (lib.getExe pkgs.pamixer) "--default-source" "-t" ]; };

        # Volume / brightness — these repeat while held.
        "XF86AudioRaiseVolume" = { _props.allow-when-locked = true; spawn = [ (lib.getExe pkgs.pamixer) "-i" "5" ]; };
        "XF86AudioLowerVolume" = { _props.allow-when-locked = true; spawn = [ (lib.getExe pkgs.pamixer) "-d" "5" ]; };
        "XF86MonBrightnessUp" = { _props.allow-when-locked = true; spawn = [ (lib.getExe pkgs.brightnessctl) "set" "+5%" ]; };
        "XF86MonBrightnessDown" = { _props.allow-when-locked = true; spawn = [ (lib.getExe pkgs.brightnessctl) "set" "5%-" ]; };
      } // wsBinds;
    }
    # Animations are a full-screen redraw. On a GPU that is free; under
    # llvmpipe (the demo VM, or a machine with no accelerated driver) it is
    # the difference between smooth and unusable.
    // lib.optionalAttrs (!cfg.animations) { animations.off = { }; };
  };

  # ─── Session services ───
  # All of these are plain systemd user units bound to graphical-session
  # .target, which niri-session starts. Nothing is spawned by the compositor,
  # so the session survives restarting the compositor and each piece can be
  # replaced without touching the niri config.
  services.polkit-gnome.enable = true;   # authentication agent
  services.blueman-applet.enable = true;

  # ─── Waybar ───
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 32;
      modules-left = [ "niri/workspaces" ];
      modules-center = [ "clock" ];
      modules-right = [
        "tray"
        "bluetooth"
        "network"
        "pulseaudio"
        "battery"
      ];
      "niri/workspaces".format = "{index}";
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
      battery.format-icons = [ "" "" "" "" "" "" ];
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
      #workspaces button.focused {
        color: #${c.mauve};
      }
      #workspaces button.active {
        color: #${c.subtext1};
      }
      #workspaces button.urgent {
        color: #${c.red};
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
    terminal=${termCmd}
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
  # swaylock speaks ext-session-lock-v1, so it is not tied to any compositor.
  # It needs security.pam.services.swaylock on the system side (see
  # ../modules/desktop.nix) or it can never accept your password.
  programs.swaylock = {
    enable = true;
    settings = {
      daemonize = true;
      show-failed-attempts = true;
      indicator-radius = 100;
      indicator-thickness = 8;
      color = c.base;
      inside-color = c.surface0;
      inside-ver-color = c.surface0;
      inside-wrong-color = c.surface0;
      ring-color = c.surface1;
      ring-ver-color = c.blue;
      ring-wrong-color = c.red;
      key-hl-color = c.mauve;
      bs-hl-color = c.red;
      text-color = c.text;
      text-ver-color = c.text;
      text-wrong-color = c.text;
      line-color = "00000000";
      separator-color = "00000000";
    };
  };

  # ─── Idle: lock at 5min, screen off at 10, suspend at 15 ───
  # swayidle speaks ext-idle-notify-v1, also compositor-independent. The
  # `lock` and `before-sleep` events mean loginctl lock-session and suspend
  # both go through the same locker.
  services.swayidle = {
    enable = true;
    timeouts = [
      { timeout = 300; command = lockCmd; }
      {
        timeout = 600;
        command = "${lib.getExe pkgs.niri} msg action power-off-monitors";
      }
      { timeout = 900; command = "${pkgs.systemd}/bin/systemctl suspend"; }
    ];
    events = {
      before-sleep = lockCmd;
      lock = lockCmd;
    };
  };

  # ─── Cursor ───
  # home.pointerCursor (rather than gtk.cursorTheme alone) also exports
  # XCURSOR_THEME/XCURSOR_SIZE and links the theme into ~/.icons, which is
  # what the compositor itself reads.
  home.pointerCursor = {
    enable = true;
    name = "Bibata-Modern-Ice";
    package = pkgs.bibata-cursors;
    size = 24;
    gtk.enable = true;
  };

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
  };
}
