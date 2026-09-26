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

    keyboard.layout = lib.mkOption {
      type = lib.types.str;
      default = "us";
      example = "fr";
      description = ''
        XKB layout, as an xkeyboard-config name ("us", "fr", "de", "gb").
        Several may be given comma-separated ("us,fr") to switch between them.

        THIS IS ONE SETTING FOR THREE KEYBOARDS, which is the reason it exists
        as an option rather than as something you run once by hand.

        niri deliberately does not carry its own copy of the layout: with an
        empty `xkb` block (see home/desktop.nix) it asks systemd-localed, and
        localed reads /etc/X11/xorg.conf.d/00-keyboard.conf. NixOS generates
        that file from `services.xserver.xkb.*` whenever
        `services.graphical-desktop.enable` is on, which greetd turns on -- so
        this flows to the compositor with no X server anywhere in sight.

        The other two keyboards are the text ones, and they are the reason
        `console.useXkbConfig` is switched on alongside: the VT (tuigreet, the
        emergency shell) and, more importantly, THE INITRD PASSPHRASE PROMPT.
        Set a LUKS passphrase containing characters that move between layouts
        and leave the console on US, and the machine becomes unbootable by its
        owner with no indication of why.
      '';
    };

    keyboard.variant = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "dvorak";
      description = "XKB variant (\"dvorak\", \"colemak\", \"nodeadkeys\"). Empty means the layout's default.";
    };

    keyboard.options = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "grp:alt_shift_toggle,caps:escape";
      description = "XKB options, comma-separated. Empty means none.";
    };

    # ── The agent layer: a local model, private search, and agents that use
    # them, for the owner and for anonymous accounts. See modules/agents.nix.

    user = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "alice";
      description = ''
        The machine's OWNER: the account the agent layer configures pi and
        wherever for, and adds to the local model's and search's groups.

        The system layer cannot know this by itself (a NixOS module is not
        told which of the declared users is the person at the keyboard), which
        is the only reason it is an option. Empty leaves those per-user parts
        off; the machine-wide services (model, search, anon accounts) do not
        depend on it.
      '';
    };

    llm.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        A local AI model on this machine: llama.cpp on the CPU, serving a small
        open-weights model (Qwen3.5 4B, Apache-2.0, ~2.7 GB download) over a
        unix socket. Prompts never leave the machine; the server itself runs
        with no network access at all.

        Every agent here is configured to use it, so the machine has a working
        assistant with no account anywhere. It is also the ONLY model the
        anonymous accounts can use without a hole in their jail.

        Costs the download and, while answering, CPU. Idle, it costs memory the
        kernel can reclaim. See wasisabi.services.llm.* to change the model.
      '';
    };

    search.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Private web search: a local SearXNG (a metasearch engine querying many
        engines at once, no account, no tracking profile) plus webveil, the
        search-and-fetch tool agents use. Also usable from a shell: `webveil`.
      '';
    };

    search.viaTor = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Send the search engines' requests through Tor, so they see a Tor exit
        rather than this machine's address.

        OFF by default because it costs results: many engines challenge or
        refuse Tor exits. Your queries are still sent without cookies or an
        account either way; this decides only which address they come from.
      '';
    };

    agents.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        The pi coding agent for the machine's owner, set up to use the local
        model and private search, with memonaut (search your past agent
        conversations) and wherever (a web UI for agent sessions, on this
        machine only: run `wherever-link` for its address).
      '';
    };

    anon.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Anonymous accounts: separate logins (anon, anon-john, anon-jane) whose
        EVERY connection is forced through Tor by the kernel, fail-closed
        (anonctl). If Tor is down, they have no network, never your address.

        Each comes with its own agent setup (pi on the local model, web search
        through its own Tor circuit) and its own wherever web UI, reachable from
        this machine: run `sudo anon-reconcile links`.

        They carry nothing of yours: no keys, no git identity, no history. Use
        one by logging in as it, or `sudo anonctl use anon`.

        Runs the Tor client even if wasisabi.tor.enable is off, since it is
        their only way out (so a Tor SOCKS port on 127.0.0.1:9050 exists for
        every local account too, as with that option). Changes how this machine
        resolves hostnames (systemd-resolved, nscd not answering host lookups),
        because otherwise every name an anon account looks up would be
        resolved in the clear by the system resolver.
      '';
    };

    anon.autoEnroll = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Put the declared anon accounts under anonctl's forcing automatically,
        at boot, instead of waiting for `sudo anonctl add <account>`.

        Until an account is enrolled it exists but is NOT forced; it is inert
        only because it has no password and no key. Enrolling makes the jail
        real, and a retry timer proves it (`anonctl verify`) once Tor is up, at
        which point each account's web UI appears. It never punches an
        exemption: the local model is reached over a unix socket, which needs
        none.
      '';
    };

    anon.accounts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            uid = lib.mkOption {
              type = lib.types.ints.between 1000 29999;
              description = "Pinned uid of the login account (the forcing matches it, so it must never drift).";
            };
            shimUid = lib.mkOption {
              type = lib.types.ints.between 400 999;
              description = "Pinned uid of the account's shim (its private relay to Tor).";
            };
          };
        }
      );
      default = {
        anon = {
          uid = 8801;
          shimUid = 412;
        };
        anon-john = {
          uid = 8802;
          shimUid = 413;
        };
        anon-jane = {
          uid = 8803;
          shimUid = 414;
        };
      };
      description = ''
        The anonymous account slots, by anonctl account name ("anon" or
        "anon-<slot>"), with pinned uids. The names are world-readable and must
        never say what an account is FOR: "john" and "jane" are placeholder
        personas. Declare the whole pool at once; a pool that grows later
        records when an identity was created.

        uids are high (away from the 1000+ normal-user front) and shim uids low
        (away from the 999- system front), so neither is ever auto-allocated.
      '';
    };
  };
}