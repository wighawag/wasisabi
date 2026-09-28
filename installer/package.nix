# The installer as a package: two entry points and the data they need.
#
#   wasisabi-install  the TUI (and the unattended --answers path)
#   wasisabi-emit     the template renderer, on its own, so the emit step can
#                     be run and diffed without a disk anywhere near it
#
# Everything variable is baked in here rather than looked up at runtime: the
# questions, the template, the pinned flake.lock and the release this medium
# installs. An installer that resolved those at runtime would be an installer
# whose output depends on the day it is run.

{
  lib,
  symlinkJoin,
  writeShellApplication,
  age,
  bash,
  ckbcomp,
  coreutils,
  cryptsetup,
  diffutils,
  disko,
  dosfstools,
  e2fsprogs,
  gawk,
  git,
  gnugrep,
  gnused,
  gptfdisk,
  gum,
  jq,
  kbd,
  mkpasswd,
  nix,
  nixos-install-tools,
  openssh,
  python3,
  sops,
  util-linux,

  questions,
  template,
  targetLock,
  secretsTool,
  stateVersion,
  nixpkgsSource,
  offline ? false,
}:

let
  emit = writeShellApplication {
    name = "wasisabi-emit";
    runtimeInputs = [
      bash
      coreutils
      gawk
      gnugrep
      gnused
      jq
      python3
      (lib.getBin util-linux)
    ];
    # Absolute, not `exec bash`: a systemd unit inherits no useful PATH, and
    # resolving the interpreter from one is how this failed the first time --
    # exit 127, eight milliseconds in, with nothing to show for it.
    text = ''
      exec ${lib.getExe bash} ${./emit.sh} "$@"
    '';
  };

  install = writeShellApplication {
    name = "wasisabi-install";
    runtimeInputs = [
      age
      bash
      ckbcomp
      coreutils
      cryptsetup
      diffutils
      disko
      dosfstools
      e2fsprogs
      gawk
      git
      gnugrep
      gnused
      gptfdisk
      gum
      jq
      kbd
      mkpasswd
      nix
      nixos-install-tools
      # ssh for a restore from a private repo or git+ssh flake inputs
      openssh
      python3
      secretsTool
      sops
      util-linux
    ];
    text = ''
      export WASISABI_QUESTIONS=${questions}
      export WASISABI_TEMPLATE=${template}
      export WASISABI_EMIT=${./emit.sh}
      export WASISABI_LOCK=${targetLock}/flake.lock
      export WASISABI_URL=${targetLock.url}
      export WASISABI_DISKO=${./disko}
      # disko evaluates its own config at runtime with `import <nixpkgs>`, and
      # a systemd unit inherits no NIX_PATH at all, so the sources travel with
      # the installer instead of being looked up in the environment.
      export WASISABI_NIXPKGS=${nixpkgsSource}
      export WASISABI_STATE_VERSION=${stateVersion}
      export WASISABI_OFFLINE=${if offline then "1" else "0"}
      exec ${lib.getExe bash} ${./install.sh} "$@"
    '';
  };
in

symlinkJoin {
  name = "wasisabi-installer";
  paths = [
    install
    emit
    # On the medium's PATH too, for `wasisabi-secrets keygen` by hand.
    secretsTool
  ];
  meta = {
    description = "Interactive installer for a wasi-sabi machine";
    mainProgram = "wasisabi-install";
  };
}
