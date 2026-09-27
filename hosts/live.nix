{
  config,
  lib,
  pkgs,
  wasisabiModules,
  ...
}:

# THE LIVE SESSION on the offline medium: the wasisabi desktop, logged in
# automatically as the installer's `nixos` user (no password, passwordless
# sudo, both from NixOS's installation-device profile), so the machine can be
# tried before anything touches its disk. Imported by hosts/iso.nix when
# `live` is set.
#
# The boot menu's default entry is this; a second entry, "text installer",
# is the old medium exactly (see `specialisation.installer` below), for a
# machine whose graphics are the problem or a person who just wants to install.
let
  # What greetd runs for the live user, at autologin and whenever someone logs
  # in again from the greeter. The render-node test is the whole point: niri
  # refuses a software renderer, so without it a GPU-less machine would show a
  # black screen with niri running perfectly behind it. This turns that into
  # a sentence on the screen and a working shell.
  #
  # WAIT FOR THE GPU DRIVER FIRST. greetd can start before udev has loaded the
  # GPU's kernel module (on the medium it is not in the initrd; amdgpu takes
  # seconds on real laptops). `udevadm settle` waits for the coldplug queue to
  # drain, and the poll covers a driver that registers its node a moment later.
  #
  # A PLAIN GLOB, NOT `compgen -G`: scripts run under nixpkgs' non-interactive
  # bash, which is built without programmable completion, so `compgen` does
  # not exist there, and the test failed silently on a machine with a GPU.
  liveSession = pkgs.writeShellScript "wasisabi-live-session" ''
    hasRenderNode() {
      local n
      for n in /dev/dri/renderD*; do
        [ -e "$n" ] && return 0
      done
      return 1
    }
    ${lib.getExe' pkgs.systemd "udevadm"} settle --timeout=30 || true
    for _ in $(seq 1 20); do
      hasRenderNode && break
      sleep 0.5
    done
    if hasRenderNode; then
      exec ${lib.getExe' pkgs.systemd "systemd-cat"} --identifier=niri-session ${lib.getExe' pkgs.niri "niri-session"}
    fi
    clear
    cat <<'MSG'

      wasi-sabi live: this machine has no usable GPU (no /dev/dri/renderD*),
      and the desktop needs one, so it was not started.

      You can still install:   sudo wasisabi-install
      Wifi:                    sudo nmtui

    MSG
    exec ${lib.getExe pkgs.bashInteractive} -l
  '';

  # Opened once when the live desktop starts: what this is, and the one
  # command that installs it.
  welcome = pkgs.writeShellScript "wasisabi-live-welcome" ''
    # Lines kept short: this opens in a tiled, half-width terminal.
    cat <<'MSG'

      Welcome to the wasi-sabi live session.

      It runs from the USB stick and from RAM.
      Nothing is written to this computer's
      disks, and nothing done here survives a
      reboot.

      Things to try:
        Super+A            the assistant, in the
                           browser (same agent)
        pi                 an AI coding agent, on a
                           model running on this CPU
                           (the first answer waits
                           while the model loads)
        webveil search ..  private web search
        sudo anonctl use anon
                           an account whose traffic
                           all goes through Tor
                           (needs a network)

      To install:  sudo wasisabi-install
      Wifi:        sudo nmtui

    MSG
    exec ${lib.getExe pkgs.bashInteractive} -l
  '';

  terminalFor =
    t:
    if t == "ghostty" then
      lib.getExe pkgs.ghostty
    else if t == "kitty" then
      lib.getExe pkgs.kitty
    else
      lib.getExe pkgs.foot;

  tuigreet = "${lib.getExe pkgs.tuigreet} --time --greeting 'wasi-sabi live: user nixos, no password.  Install: sudo wasisabi-install' --cmd ${liveSession}";
in
{
  networking.hostName = "wasisabi-live";

  wasisabi = {
    enable = true;
    user = "nixos";
    # The text greeter, whatever the default: it is the one that still works
    # when the GPU is the problem, and it only shows after a logout anyway.
    greetd.greeter = "tuigreet";
    # The medium has its own boot screen; Plymouth would only hide it.
    splash.enable = false;
  };

  # RAM is the scarce thing in a live session (every file written lives in
  # it), so the model loads on first use rather than at boot.
  nixos-modules.llm.onDemand = true;

  # The live user has PASSWORDLESS sudo (NixOS's installation-device profile),
  # so a working sudo in wherever sessions would be root for any agent.
  nixos-modules.wherever.allowPrivilegeEscalation = false;

  services.greetd.settings = {
    initial_session = {
      user = "nixos";
      command = "${liveSession}";
    };
    default_session.command = tuigreet;
  };

  # UNDO WHAT THE MINIMAL INSTALLER PROFILE TURNS OFF, which a desktop needs:
  # without fontconfig nothing finds a font, without the xdg pieces there are
  # no icons, no "open with" and no autostart, and without udisks2 the file
  # manager cannot mount a USB stick. Normal priority beats the profile's
  # mkDefault and mkOverride 500.
  fonts.fontconfig.enable = true;
  xdg = {
    autostart.enable = true;
    icons.enable = true;
    mime.enable = true;
    sounds.enable = true;
  };
  services.udisks2.enable = true;

  # No keyring. On an installed machine the login password unlocks it; the
  # live session logs in with no password, so gnome-keyring greeted the
  # desktop with "choose a password for a new keyring". Nothing here outlives
  # the session anyway. (niri's module enables it at mkDefault.)
  services.gnome.gnome-keyring.enable = false;

  home-manager.users.nixos = {
    imports = [ wasisabiModules.home ];
    wasisabi.enable = true;

    systemd.user.services.wasisabi-live-welcome = {
      Unit = {
        Description = "wasi-sabi live welcome";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        # After Noctalia's own first-login intro, not on top of it: one thing
        # at a time (the assistant's welcome notification waits the same way).
        ExecStart = "${lib.getExe config.home-manager.users.nixos.wasisabi.afterNoctaliaIntro} ${terminalFor config.home-manager.users.nixos.wasisabi.terminal} -e ${welcome}";
        Restart = "no";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };

  # THE TEXT-ONLY BOOT ENTRY: the old medium, exactly. No desktop, no agent
  # layer, getty autologin as before, so a machine whose graphics misbehave in
  # a way the render-node test cannot see still installs.
  isoImage.configurationName = "live desktop";
  specialisation.installer.configuration = {
    isoImage.configurationName = lib.mkForce "text installer only";
    wasisabi.enable = lib.mkForce false;
    services.greetd.enable = lib.mkForce false;
    home-manager.users = lib.mkForce { };
  };
}
