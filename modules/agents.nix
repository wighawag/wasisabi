{
  config,
  lib,
  pkgs,
  ...
}:

# THE AGENT LAYER, as a wasisabi machine gets it: the building blocks in
# ./services switched on and wired to each other, from the handful of
# distro-level options in ./options.nix (llm, search, agents, anon).
#
# Everything is mkDefault, like the rest of wasisabi, so any value a machine
# sets wins; and every building block remains usable on its own for a machine
# that wants a different arrangement.
#
# THE SHAPE, in one picture:
#
#   llama.cpp ── /run/wasisabi-llm/llm.sock ──┬─ owner's pi / wherever  (group)
#   (no network)                              └─ anon accounts' pi      (group)
#
#   SearXNG ──── /run/wasisabi-search/search.sock ── owner's webveil / pi
#   SearXNG per anon account, as that account ── its own Tor circuit
#
#   anon accounts: every packet forced through Tor by anonctl, fail-closed;
#   each with a wherever on a socket, routed by a loopback-only Caddy at
#   http://<handle>.localhost:8480/#token=...
#
# The local model is reached over a UNIX SOCKET throughout, which is what lets
# the anon accounts use it with NO exemption in their jail: a unix socket is
# not IP traffic, so the kernel's forcing never sees it. Access is the socket's
# group, which this module grants to the owner and to each anon account.
let
  cfg = config.wasisabi;
  svc = config.wasisabi.services;
  wp = config.wasisabi.pkgs;
  hasUser = cfg.user != "";

  llmModels = [
    {
      id = svc.llm.modelId;
      name = svc.llm.modelName;
      reasoning = svc.llm.reasoning;
      vision = svc.llm.mmproj != null;
      contextWindow = svc.llm.contextSize;
      maxTokens = svc.llm.maxTokens;
    }
  ];

  torSocks = "socks5h://127.0.0.1:9050";

  enrollScript = pkgs.writeShellScript "wasisabi-anon-enroll" ''
    # Idempotent, and self-healing, per declared account:
    #
    #   proven (a marker exists)          nothing to do; reconcile's own timer
    #                                     keeps checking the jail is loaded
    #   managed, forcing loaded           prove it (`verify`, which writes the
    #                                     marker on green)
    #   managed, forcing NOT loaded       a failed `add` (it records the account
    #                                     before installing the rules): remove
    #                                     and add again. Safe precisely because
    #                                     it was never proven, so reconcile never
    #                                     gave it an interface, a handle or a
    #                                     token that `rm` could take away.
    #   not managed                       `add` (adopting the declared account)
    #
    # Never fails the unit: an account that cannot be proven yet (Tor still
    # bootstrapping, no network) is retried by the timer, and until it is
    # proven it gets no interface, which is the safe direction.
    set -u
    anonctl=${lib.getExe wp.anonctl}
    jq=${lib.getExe pkgs.jq}
    for account in ${lib.escapeShellArgs (lib.attrNames cfg.anon.accounts)}; do
      [ -e "/etc/anonctl/$account.json" ] && continue
      if [ -e "/etc/anonctl/accounts/$account.json" ]; then
        state=$("$anonctl" status "$account" --json 2>/dev/null | "$jq" -r '.forcing.state // "unknown"')
        if [ "$state" = forced ]; then
          echo "proving $account"
          "$anonctl" verify "$account" >/dev/null || echo "verify $account is not green yet; will retry" >&2
          continue
        fi
        echo "$account is managed but its forcing is $state (a failed add); re-installing it"
        "$anonctl" rm "$account" || { echo "rm $account failed; will retry" >&2; continue; }
      fi
      echo "enrolling $account"
      "$anonctl" add --endpoint ${torSocks} "$account" || echo "add $account failed; will retry" >&2
    done
    exit 0
  '';
in
lib.mkIf cfg.enable (
  lib.mkMerge [
    # ── the local model ──
    (lib.mkIf cfg.llm.enable {
      wasisabi.services.llm.enable = lib.mkDefault true;
    })

    # ── private search ──
    (lib.mkIf cfg.search.enable {
      wasisabi.services.searxng = {
        enable = lib.mkDefault true;
        egressProxies = lib.mkIf cfg.search.viaTor (lib.mkDefault [ torSocks ]);
        requestTimeout = lib.mkIf cfg.search.viaTor (lib.mkDefault 10.0);
      };
      environment.systemPackages = [ wp.webveil ];
    })

    # ── the owner's agent ──
    (lib.mkIf (cfg.agents.enable && hasUser) {
      wasisabi.services.piUser = {
        enable = lib.mkDefault true;
        user = lib.mkDefault cfg.user;
        extensions = {
          memonaut-pi = lib.mkDefault wp.memonaut-pi;
          pi-webveil = lib.mkIf cfg.search.enable (lib.mkDefault wp.pi-webveil);
          pi-wasisabi-local = lib.mkIf cfg.llm.enable (lib.mkDefault wp.pi-wasisabi-local);
        };
        settings = lib.mkIf cfg.llm.enable (
          lib.mkDefault {
            defaultProvider = svc.llm.providerId;
            defaultModel = svc.llm.modelId;
          }
        );
        webveilConfig = lib.mkIf cfg.search.enable (
          lib.mkDefault {
            backend = "searxng";
            baseUrl = svc.searxng.baseUrl;
            # The BACKEND hop is a local socket; proxying it would be fake
            # anonymity, and webveil refuses the combination.
            egress.mode = "direct";
          }
        );
      };

      wasisabi.services.wherever = {
        enable = lib.mkDefault true;
        user = lib.mkDefault cfg.user;
      };

      environment.systemPackages = [ wp.memonaut ];
    })

    # The owner reaches the socket-served services through their groups.
    (lib.mkIf hasUser {
      users.users.${cfg.user}.extraGroups =
        lib.optional svc.llm.enable svc.llm.clientGroup
        ++ lib.optional svc.searxng.enable svc.searxng.clientGroup;
    })

    # ── anonymous accounts ──
    (lib.mkIf cfg.anon.enable {
      # The anon accounts' only way out, so they bring it: the same loopback
      # client wasisabi.tor.enable configures (nixpkgs' defaults: 127.0.0.1:9050,
      # per-destination circuit isolation), switched on even when that option
      # is off. anonctl additionally isolates each account on its own circuits.
      services.tor = {
        enable = lib.mkDefault true;
        client.enable = lib.mkDefault true;
      };

      assertions = [
        {
          assertion = config.services.tor.enable && config.services.tor.client.enable;
          message = ''
            wasisabi.anon.enable needs the Tor client (services.tor.client), and
            something turned it off: it is the endpoint every anon account's
            traffic is forced through. Without it the accounts would be jailed
            with no way out, which is safe but useless. Turn wasisabi.anon.enable
            off instead.
          '';
        }
      ];

      # nft too: anonctl runs it by name, and NixOS does not put it on the
      # system PATH unless the firewall backend happens to be nftables.
      environment.systemPackages = [
        wp.anonctl
        pkgs.nftables
      ];

      wasisabi.services.anonAccounts = {
        enable = lib.mkDefault true;
        accounts = lib.mkDefault cfg.anon.accounts;
      };
      wasisabi.services.anonctlUnits = {
        enable = lib.mkDefault true;
        package = lib.mkDefault wp.anonctl;
      };
      wasisabi.services.anonDns.enable = lib.mkDefault true;

      wasisabi.services.anonHome = {
        enable = lib.mkDefault true;
        # web_fetch needs no backend and leaves through the account's own
        # circuit; web_search uses the per-account SearXNG below.
        webTools = {
          enable = lib.mkDefault true;
          package = lib.mkDefault wp.pi-webveil;
        };
        extensions = {
          memonaut-pi = lib.mkDefault wp.memonaut-pi;
          pi-wasisabi-local = lib.mkIf cfg.llm.enable (lib.mkDefault wp.pi-wasisabi-local);
        };
        provider = lib.mkDefault svc.llm.providerId;
        models = lib.mkIf cfg.llm.enable (lib.mkDefault llmModels);
        defaultModel = lib.mkIf cfg.llm.enable (lib.mkDefault svc.llm.modelId);
      };

      wasisabi.services.anonSearch.enable = lib.mkDefault true;

      wasisabi.services.whereverAnon = {
        enable = lib.mkDefault true;
        reconcile.enable = lib.mkDefault true;
      };
      wasisabi.services.anonDispatcher.enable = lib.mkDefault true;

      # Each anon account may reach the local model's socket, and nothing else
      # of the owner's.
      users.users = lib.mkIf svc.llm.enable (
        lib.mapAttrs (_: _: { extraGroups = [ svc.llm.clientGroup ]; }) cfg.anon.accounts
      );
    })

    (lib.mkIf (cfg.anon.enable && cfg.anon.autoEnroll) {
      systemd.services.wasisabi-anon-enroll = {
        description = "Enrol and prove the declared anon accounts (anonctl add / verify)";
        # NOT wanted by multi-user.target: `verify` waits on Tor, and a boot
        # must never wait on Tor. The timer below starts it shortly after boot.
        wants = [ "network-online.target" ];
        after = [
          "network-online.target"
          "tor.service"
          "anonctl-nftables.service"
          "nscd.service"
        ];
        # anonctl execs nft, setpriv and nologin by name, and a unit's PATH
        # holds none of them: without these every `add` failed at its first
        # step (measured in the demo VM).
        path = [
          wp.anonctl
          pkgs.nftables
          "/run/current-system/sw"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = enrollScript;
          # verify makes real connections through Tor; give a slow first
          # bootstrap room rather than a hung boot.
          TimeoutStartSec = "10min";
        };
      };
      systemd.timers.wasisabi-anon-enroll = {
        description = "Retry proving anon accounts that are not proven yet";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitInactiveSec = "15min";
          Unit = "wasisabi-anon-enroll.service";
        };
      };
    })
  ]
)
