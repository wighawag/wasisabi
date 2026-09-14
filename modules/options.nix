{ lib, ... }:

{
  options.wasisabi = {
    enable = lib.mkEnableOption "the wasisabi system layer";

    enforceLibre = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Fail the build if `nixpkgs.config.allowUnfree = true`.
        This enforces the project rule: open source software only.
      '';
    };

    greetd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "greetd as the login manager.";
    };

    greetd.greeter = lib.mkOption {
      type = lib.types.enum [ "noctalia" "tuigreet" ];
      default = "noctalia";
      description = ''
        Which greeter greetd launches.

        "noctalia" is the graphical greeter from the Noctalia project
        (packaged in nixpkgs): user and session pickers, password entry and a
        colour-scheme chooser, in the same visual language as the shell. It
        brings its OWN bundled wlroots compositor, so it needs a GPU with a
        render node, exactly like the session it logs you into.

        "tuigreet" is a text greeter that runs on the VT. Uglier, and the one
        that still works when the graphics stack is the thing that is broken
        -- which is why it stays available rather than being deleted.

        This pairs with the HOME-layer `wasisabi.shell` option but is
        deliberately independent of it: the greeter runs as its own user
        before any home configuration exists, so the two cannot read each
        other and a fleet may reasonably want a text greeter with a graphical
        session or the reverse.
      '';
    };

    splash.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Plymouth splash screen and a quiet boot, themed to match the desktop.

        This hides routine unit and kernel output, not failures: password
        prompts, fsck questions and the emergency shell still appear. Set to
        false if you would rather watch the boot.
      '';
    };

    zram.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "zram swap (compressed RAM swap — no disk layout needed, safe everywhere).";
    };

    bluetooth.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Bluetooth stack (harmless if the machine has no adapter).";
    };

    cellular.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "ModemManager for WWAN/LTE modems (harmless if absent).";
    };

    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "Europe/London";
      description = "Default timezone. mkDefault — override freely.";
    };

    locale = lib.mkOption {
      type = lib.types.str;
      default = "en_GB.UTF-8";
      description = "Default locale. mkDefault — override freely.";
    };
  };
}