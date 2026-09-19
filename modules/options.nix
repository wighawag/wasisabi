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

    printing.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        CUPS plus DRIVERLESS printer discovery (IPP Everywhere / AirPrint over
        DNS-SD). Finds any printer made since roughly 2010 with no vendor
        driver and no configuration.

        Driverless is not merely the tidy option here, it is what keeps
        printing COMPATIBLE WITH THE LIBRE RULE. Most vendor PPDs and filters
        in nixpkgs are unfree (Epson's escpr2, for one), so a driver-based
        setup would force a wasisabi user to choose between printing and
        `enforceLibre`. Asking the printer to describe itself over IPP removes
        that choice instead of trading it away.

        No queue is created declaratively, deliberately: building one requires
        contacting the device, so a printer that is switched off would fail the
        activation. Discovery has no such coupling.
      '';
    };

    tor.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        A Tor CLIENT exposing SOCKS5 on 127.0.0.1:9050. Client only: this is
        never a relay, a bridge or an onion service, so the machine carries
        nobody else's traffic and gains no abuse or legal surface from it.

        ON BY DEFAULT because it fits what this setup is for: an endpoint that
        can be reached without an account attached to it is exactly the kind of
        capability a libre, self-hostable desktop should have sitting there,
        and nothing uses it until something asks. The daemon is small and
        idles cheaply.

        BE HONEST ABOUT TWO THINGS. It does not make the machine anonymous:
        your browser, your logins and your ordinary traffic are untouched and
        still fully attributable. And running it is VISIBLE TO YOUR ISP, since
        connections to Tor guards are recognisable; in a few jurisdictions that
        is itself worth avoiding, which is a reason to set this false rather
        than a reason nobody should have it on.
      '';
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