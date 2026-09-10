{ lib, ... }:

{
  options.wasisabi = {
    enable = lib.mkEnableOption "the wasisabi home layer (apps + dotfiles)";

    modKey = lib.mkOption {
      type = lib.types.enum [ "SUPER" "ALT" "CTRL" ];
      default = "SUPER";
      description = ''
        Primary modifier for all keybinds.
        Use "ALT" when testing in a VM: host desktops swallow Super+...
        before QEMU can see them.
      '';
    };

    animations = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Compositor animations (window open/close, workspace switch, strip
        scrolling, overview).

        Turn this off on machines with no accelerated GPU driver: under
        llvmpipe every animation frame is a full-screen CPU blit, which is
        the difference between smooth and unusable. The demo VM sets this
        to false for exactly that reason.
      '';
    };

    terminal = lib.mkOption {
      type = lib.types.enum [ "ghostty" "foot" ];
      default = "ghostty";
      description = "Terminal emulator.";
    };

    editor = lib.mkOption {
      type = lib.types.enum [ "neovim" "helix" ];
      default = "neovim";
      description = "Default $EDITOR (both are installed either way).";
    };

    browser = lib.mkOption {
      type = lib.types.enum [ "firefox" "librewolf" "chromium" "none" ];
      default = "firefox";
      description = "Web browser. All FOSS builds, no vendor telemetry.";
    };

    fileManager = lib.mkOption {
      type = lib.types.enum [ "thunar" "nautilus" "none" ];
      default = "thunar";
      description = "Graphical file manager.";
    };

    apps.media = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Media: mpv (video) + imv (images).";
    };

    apps.office = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "LibreOffice suite.";
    };

    apps.email = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Thunderbird (IMAP — works with any provider incl. self-hosted).";
    };

    apps.passwords = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "KeePassXC — local-first password database (no cloud service).";
    };

    apps.syncthing = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Syncthing — peer-to-peer sync, self-hostable by design.";
    };
  };
}