{ lib, pkgs, config, osConfig ? null, ... }:

# THE ASSISTANT, MADE VISIBLE. The system layer (../modules/agents.nix) runs a
# wherever for the machine's owner: a web UI for pi agent sessions on the
# local model, loopback only. Until now the only way to find it was to know
# that `wherever-link` exists. This module puts it where a new user looks:
#
#   - a launcher entry ("Assistant"), in fuzzel and in Noctalia's launcher
#   - a keybind, Mod+A
#   - a bar button (Waybar here; Noctalia's comes from its seed, see noctalia.nix)
#   - a one-time welcome notification on the first graphical login
#
# All four run the same command, `wasisabi-assistant`, which asks
# `wherever-link` for the URL AT CLICK TIME. That is the one design constraint:
# the URL carries the access token (in the fragment, which a browser never
# sends), the token is minted on the machine at first start and readable only
# by the owner, and it must never reach the store. So nothing here may bake the
# URL into a file; a bookmark or a browser homepage set at build time would
# have to. Resolving it on each click also means a token rotation (delete
# /var/lib/wherever/token, restart wherever) is picked up with no rebuild.
#
# WHY KEEP THE TOKEN AT ALL on a loopback-only server, when a mesh-only box
# (the fleet's telemaque) runs without one: loopback is not a boundary against
# THIS machine's browsers. wherever answers with `Access-Control-Allow-Origin:
# *` and does not check Host, so without a token any web page open in any
# local browser could drive an agent with full access to the owner's home,
# directly or by DNS rebinding. Two such browsers are always here: the owner's
# own, and webhands' Chromium, which agents point at arbitrary pages. On a mesh
# box, those browsers are not on the same host as the server; here they are.
let
  cfg = config.wasisabi;

  # On by default exactly when this home belongs to the account the system
  # layer runs wherever for. Standalone home-manager (no NixOS underneath) has
  # no osConfig and no wherever, so it is off there.
  ownsWherever =
    osConfig != null
    && (osConfig.nixos-modules.wherever.enable or false)
    && (osConfig.nixos-modules.wherever.user or "") == config.home.username;

  noctalia = cfg.shell == "noctalia";

  # How the bind reads to a person: "Super+A", not "SUPER+A".
  keyName = { SUPER = "Super"; ALT = "Alt"; CTRL = "Ctrl"; }.${cfg.modKey};

  # One path, used by the script and by the unit's condition.
  stampRel = ".local/state/wasisabi/assistant-welcomed";

  browserCmd =
    if cfg.browser == "firefox" then lib.getExe pkgs.firefox
    else if cfg.browser == "librewolf" then lib.getExe pkgs.librewolf
    else if cfg.browser == "chromium" then lib.getExe pkgs.chromium
    else "${pkgs.xdg-utils}/bin/xdg-open";

  open = pkgs.writeShellApplication {
    name = "wasisabi-assistant";
    runtimeInputs = [ pkgs.libnotify pkgs.coreutils ];
    text = ''
      # wherever-link comes from the system profile, which a session spawned
      # by the compositor may not have on PATH.
      PATH="$PATH:/run/current-system/sw/bin"

      # Right after boot wherever may still be minting its token, so give it a
      # few seconds before reporting a failure.
      url=""
      for _ in $(seq 1 10); do
        if url=$(wherever-link 2>/dev/null); then break; fi
        url=""
        sleep 1
      done

      if [ -z "$url" ]; then
        notify-send --app-name=wasisabi "Assistant unavailable" \
          "wherever is not running. Check it with: systemctl status wherever"
        exit 1
      fi

      exec ${browserCmd} "$url"
    '';
  };

  welcome = pkgs.writeShellApplication {
    name = "wasisabi-assistant-welcome";
    runtimeInputs = [ pkgs.libnotify pkgs.coreutils pkgs.gnugrep pkgs.systemd ];
    text = ''
      stamp="$HOME/${stampRel}"
      [ -e "$stamp" ] && exit 0

      # The notification daemon (mako or Noctalia) is another unit of the same
      # session and may not own its bus name yet. Without one there is nobody
      # to show the welcome to, so leave the stamp alone and try next login.
      for _ in $(seq 1 30); do
        if busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
             org.freedesktop.DBus NameHasOwner s org.freedesktop.Notifications 2>/dev/null \
             | grep -q true; then
          ready=1
          break
        fi
        sleep 1
      done
      [ "''${ready:-0}" = 1 ] || exit 0

      # Stamped BEFORE showing, so it is once even if the session ends while
      # the notification is up.
      mkdir -p "$(dirname "$stamp")"
      touch "$stamp"

      action=$(notify-send --app-name=wasisabi --expire-time=0 --wait \
        --action=default="Open the assistant" \
        "Your assistant is ready" \
        "An AI that runs on this computer: no account, nothing sent to a cloud. It can search the web privately, read and write your files, and run commands when you ask. Open it any time with ${keyName}+A, from the launcher, or from the bar." \
        || true)

      if [ "$action" = default ]; then
        exec ${lib.getExe open}
      fi
    '';
  };
in
{
  options.wasisabi.assistant = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = ownsWherever;
      defaultText = lib.literalMD "true when this home's user is the one the system runs wherever for";
      description = ''
        Make the local assistant (wherever, the web UI for pi agent sessions)
        reachable from the desktop: an "Assistant" launcher entry, Mod+A, a
        bar button, and a one-time welcome notification. Each opens the
        browser on `wherever-link`'s URL, resolved when clicked, so the access
        token never reaches the store.
      '';
    };

    welcome = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Show a welcome notification introducing the assistant on the first
        graphical login, once. Delete ~/${stampRel} to see it again.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.assistant.enable) (lib.mkMerge [
    {
      home.packages = [ open ];

      # The launcher entry. Both fuzzel and Noctalia's launcher list XDG
      # desktop entries, so this one definition serves both shells.
      xdg.desktopEntries.wasisabi-assistant = {
        name = "Assistant";
        genericName = "Local AI assistant";
        comment = "The AI assistant running on this computer (wherever, on the local model)";
        exec = lib.getExe open;
        icon = "internet-chat";
        terminal = false;
        categories = [ "Utility" ];
        settings.Keywords = "ai;agent;assistant;chat;pi;wherever;llm;";
      };

      # Mod+A: free in desktop.nix, and "A" for assistant.
      wayland.windowManager.niri.settings.binds."Mod+A".spawn = lib.getExe open;
    }

    # The bar button, classic stack. Leftmost of the right-hand modules, so it
    # sits apart from the status indicators.
    (lib.mkIf (!noctalia) {
      programs.waybar.settings.mainBar = {
        modules-right = lib.mkBefore [ "custom/assistant" ];
        "custom/assistant" = {
          format = "󰚩";
          tooltip-format = "Assistant (${keyName}+A)";
          on-click = lib.getExe open;
        };
      };
      programs.waybar.style = lib.mkAfter ''
        #custom-assistant { padding: 0 8px; color: #cba6f7; }
      '';
    })

    (lib.mkIf cfg.assistant.welcome {
      systemd.user.services.wasisabi-assistant-welcome = {
        Unit = {
          Description = "Introduce the local assistant, once";
          After = [ config.wayland.systemd.target ];
          PartOf = [ config.wayland.systemd.target ];
          ConditionPathExists = "!%h/${stampRel}";
        };
        Service = {
          Type = "simple";
          ExecStart = lib.getExe welcome;
          Restart = "no";
        };
        Install.WantedBy = [ config.wayland.systemd.target ];
      };
    })
  ]);
}
