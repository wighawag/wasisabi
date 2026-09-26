{
  config,
  lib,
  pkgs,
  ...
}:

# A LOCAL MODEL SERVER: llama.cpp on the CPU, on the same machine, serving the
# OpenAI-compatible API over a UNIX SOCKET.
#
# WHY A UNIX SOCKET RATHER THAN A PORT, which is the whole shape of this module.
#
#   1. It is the only interface an anonctl-jailed account can reach without a
#      hole being punched in its jail. Every TCP connection an anon uid opens,
#      loopback included, is redirected into that account's Tor shim unless an
#      explicit `anonctl --allow 127.0.0.1:<port>` exemption says otherwise. A
#      unix socket is not IP traffic and traverses no nftables chain, so the
#      anon accounts reach the model with no exemption at all, gated by the
#      socket's GROUP instead (see `clientGroup`).
#   2. Access control is a file permission. A loopback port is open to every
#      local uid; the socket is open to its group.
#   3. The server needs no network, so it gets none: `PrivateNetwork = true`
#      puts llama-server in an empty network namespace. The process holding
#      every prompt on this machine cannot open a connection to anywhere,
#      which is a property a bound-to-loopback server can only promise.
#
# THE TCP PORT IS THE FALLBACK, not the design: most clients speak HTTP to a
# host:port and nothing else. `tcpPort` (on by default) adds a socket-activated
# `systemd-socket-proxyd` on 127.0.0.1 that forwards to the unix socket, for
# those clients. pi does NOT need it: the `pi-wasisabi-local` extension (see
# pkgs/pi-wasisabi-local) speaks HTTP over the socket directly. An anon account
# that must use the port needs the exemption, applied as root:
#
#   sudo anonctl update <account> --allow 127.0.0.1:<tcpPort>
#
# CPU BY DEFAULT, deliberately: this is a distro default, and the one
# accelerator every machine has is its CPU. The default model is small enough
# (a 4B model, ~2.7 GB at Q4_K_M) to answer at a usable speed on a laptop, and
# `model` swaps in anything llama.cpp loads. A machine with a GPU sets
# `package = pkgs.llama-cpp.override { vulkanSupport = true; }` or similar.
let
  cfg = config.wasisabi.services.llm;

  socketDir = "/run/wasisabi-llm";

  # The llama-server command line. `--host` ending in `.sock` is llama.cpp's
  # own switch to AF_UNIX (tools/server/server-http.cpp), so no wrapper is
  # needed to serve the socket.
  serverArgs = [
    "--host"
    cfg.socketPath
    "--model"
    "${cfg.model}"
    "--alias"
    cfg.modelId
    "--ctx-size"
    (toString cfg.contextSize)
    # Chat templates from the GGUF itself, which is what tool calling needs:
    # without --jinja the server falls back to a generic template that cannot
    # express tool calls, and an agent gets text where it expected a call.
    "--jinja"
    "--reasoning"
    (if cfg.reasoning then "on" else "off")
    # The browser UI would be served on the socket too, where nothing but a
    # proxy could reach it. Off: the API is the product here.
    "--no-webui"
  ]
  ++ lib.optionals (cfg.threads != null) [
    "--threads"
    (toString cfg.threads)
  ]
  ++ lib.optionals (cfg.mmproj != null) [
    "--mmproj"
    "${cfg.mmproj}"
  ]
  ++ cfg.extraArgs;

  # What a client needs to know to talk to this server, as one world-readable
  # file. No secret is involved: the socket's permissions are the access
  # control. Read by the pi extension, and by anything else that wants it.
  clientConfig = {
    provider = cfg.providerId;
    socketPath = cfg.socketPath;
    tcpUrl = if cfg.tcpPort == null then null else "http://127.0.0.1:${toString cfg.tcpPort}/v1";
    models = [
      {
        id = cfg.modelId;
        name = cfg.modelName;
        reasoning = cfg.reasoning;
        input = [ "text" ] ++ lib.optional (cfg.mmproj != null) "image";
        contextWindow = cfg.contextSize;
        maxTokens = cfg.maxTokens;
      }
    ];
  };
in
{
  options.wasisabi.services.llm = {
    enable = lib.mkEnableOption "a local llama.cpp model server on a unix socket";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-cpp;
      defaultText = lib.literalExpression "pkgs.llama-cpp";
      description = "The llama.cpp build providing `llama-server`. The nixpkgs default is a CPU build.";
    };

    model = lib.mkOption {
      type = lib.types.path;
      default = pkgs.fetchurl {
        name = "Qwen3.5-4B-Q4_K_M.gguf";
        # Pinned by commit, not by branch: a model is a large binary whose
        # behaviour an agent depends on, so it moves when this line moves.
        url = "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/e87f176479d0855a907a41277aca2f8ee7a09523/Qwen3.5-4B-Q4_K_M.gguf";
        # The LFS object id Hugging Face publishes, which is the file's sha256.
        sha256 = "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4";
      };
      defaultText = lib.literalExpression "Qwen3.5-4B Q4_K_M (unsloth GGUF, Apache-2.0), fetched and pinned by hash";
      description = ''
        The GGUF weights, as a store path (so the model is pinned, verified and
        rolled back like any other package), or any path llama.cpp can read.

        The default is Qwen3.5 4B at Q4_K_M: Apache-2.0, so it satisfies the
        libre rule; tool-calling capable; ~2.7 GB, which a laptop CPU answers
        at an interactive speed. A machine with more memory is better served by
        a mixture-of-experts model with few ACTIVE parameters (Qwen3.6-35B-A3B
        runs at small-model speed on a CPU, if you have ~24 GB to hold it).
      '';
    };

    mmproj = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The multimodal projector matching `model`, which makes the server accept
        images. Null (the default) serves text only and saves the download; set
        it and the model is advertised to clients as accepting images.
      '';
    };

    modelId = lib.mkOption {
      type = lib.types.str;
      default = "qwen3.5-4b";
      description = "The id the server advertises at /v1/models (llama-server's --alias), and what clients select.";
    };

    modelName = lib.mkOption {
      type = lib.types.str;
      default = "Qwen3.5 4B (local, CPU)";
      description = "Display name clients show for the model.";
    };

    providerId = lib.mkOption {
      type = lib.types.str;
      default = "local";
      description = "The provider name clients (pi) register this server under.";
    };

    contextSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 32768;
      description = ''
        Context window in tokens, allocated up front by llama-server. An agent's
        system prompt plus tool definitions alone is several thousand tokens, so
        much below 16k is not usable for agentic work. Memory cost grows with it.
      '';
    };

    maxTokens = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8192;
      description = "Maximum output tokens clients are told to request.";
    };

    reasoning = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether the model thinks before answering (llama-server `--reasoning`).
        OFF by default because this is a CPU: a thinking model spends most of
        its time on tokens nobody reads, which on a laptop is the difference
        between an answer and a wait. Turn it on for a model on faster hardware.
      '';
    };

    threads = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "CPU threads for generation. Null lets llama.cpp choose (the number of physical cores).";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra llama-server arguments, appended last.";
    };

    socketPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${socketDir}/llm.sock";
      description = ''
        READ-ONLY: where the server listens. Exposed so every consumer (the pi
        extension, the anon homes, the TCP fallback) reads one value rather
        than restating a path.
      '';
    };

    clientGroup = lib.mkOption {
      type = lib.types.str;
      default = "wasisabi-llm";
      description = ''
        The group allowed to CONNECT to the socket. Add a user to it and that
        user's processes can use the model; that is the entire access control.
        The anon accounts are added by the anon layer, because a unix socket is
        the one way they reach the model without an exemption in their jail.
      '';
    };

    tcpPort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = 11435;
      description = ''
        A loopback TCP port forwarding to the socket, for clients that can only
        speak to a host:port. Null disables it.

        Loopback is reachable by every local uid, so this widens access from
        "the socket's group" to "any local account that is not jailed". An
        anonctl account can use it only through an exemption applied as root
        (`anonctl update <account> --allow 127.0.0.1:<port>`); nothing here
        applies one.

        11435, not 11434: that one is ollama's, and a machine may run both.
      '';
    };

    clientConfigFile = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "/etc/wasisabi/llm.json";
      description = ''
        READ-ONLY: a world-readable JSON file describing this server (socket,
        optional TCP URL, model id and capabilities), which the pi extension
        reads so that pi's provider entry cannot drift from what is served.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${cfg.clientGroup} = { };
    users.users.wasisabi-llm = {
      isSystemUser = true;
      group = cfg.clientGroup;
      description = "wasisabi local model server";
    };

    environment.etc."wasisabi/llm.json".text = builtins.toJSON clientConfig;

    systemd.services.wasisabi-llm = {
      description = "Local model server (llama.cpp, unix socket)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/llama-server ${lib.escapeShellArgs serverArgs}";
        # llama-server creates the socket itself; wait until it exists so a
        # unit ordered after this one does not race the model load.
        ExecStartPost = pkgs.writeShellScript "wasisabi-llm-wait" ''
          for _ in $(seq 1 600); do
            [ -S ${cfg.socketPath} ] && exit 0
            sleep 0.2
          done
          echo "wasisabi-llm: ${cfg.socketPath} did not appear within 120s" >&2
          exit 1
        '';
        Restart = "on-failure";
        RestartSec = "5s";
        User = "wasisabi-llm";
        Group = cfg.clientGroup;
        # The socket inherits this: owner and group rw, nobody else.
        UMask = "0007";
        RuntimeDirectory = "wasisabi-llm";
        RuntimeDirectoryMode = "0750";

        # NO NETWORK AT ALL: see the module header. The socket is a file, so
        # it is reachable from the host namespace regardless.
        PrivateNetwork = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        IPAddressDeny = "any";

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        # Inference is CPU work; never let it starve the desktop.
        Nice = 5;
        CPUWeight = 50;
      };
    };

    # The TCP fallback, socket-activated so it costs nothing until used.
    systemd.sockets.wasisabi-llm-tcp = lib.mkIf (cfg.tcpPort != null) {
      description = "Loopback TCP entry to the local model server";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "127.0.0.1:${toString cfg.tcpPort}" ];
    };
    systemd.services.wasisabi-llm-tcp = lib.mkIf (cfg.tcpPort != null) {
      description = "Forward loopback TCP to the local model server's unix socket";
      requires = [ "wasisabi-llm.service" ];
      after = [ "wasisabi-llm.service" ];
      serviceConfig = {
        ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd ${cfg.socketPath}";
        DynamicUser = true;
        SupplementaryGroups = [ cfg.clientGroup ];
        PrivateNetwork = false;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };
}
