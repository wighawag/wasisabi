# The installer ISO, in two variants.
#
# NO LIVE DESKTOP, AND THAT IS A DECISION RATHER THAN AN OMISSION. niri
# refuses to run on a software EGL renderer, so a graphical installer ISO
# would show a black screen on exactly the machines people try it on first
# (QEMU without virtio-vga-gl, anything with no render node) while niri sat
# there running perfectly with a live Wayland socket. A text installer that
# always works beats a graphical one that fails in a way nobody can read. The
# installed system is the graphical thing; the medium that installs it is not.
#
# Variants:
#   netinstall  small (~1G). Evaluates from the sources on the medium, fetches
#               packages from cache.nixos.org. Needs a network.
#   offline     large. Carries the package closures too, so a machine with no
#               network at all still gets the same system.
#
# Both carry the wasisabi source and the pinned lock, so the ISO installs the
# exact revision it was built from rather than whatever is on the internet
# today.

{
  config,
  lib,
  pkgs,
  modulesPath,
  installer,
  nixpkgsSource,
  # Every flake source the generated config refers to, wasisabi's own
  # included. Without these the medium carries a lock that names store paths
  # it does not have, and the install dies at the last step asking to change
  # the lock file -- which is exactly what a pinned install must not do.
  sources,
  wasisabiRev,
  offline ? false,
  payloads ? [ ],
  # Unattended install, for the end-to-end VM test. Never set on media meant
  # for a person: it partitions the disk named in the answers file without
  # asking, which is precisely what you do not want a stray USB stick doing.
  autotest ? null,
  ...
}:

{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  # `image.baseName`, not `isoImage.isoName`: the latter still evaluates but is
  # renamed, and setting it produces a deprecation warning plus a filename that
  # comes from somewhere else entirely.
  # The autotest image must be impossible to mistake for real media, by name
  # and by volume label. It installs unattended with no confirmation, so a
  # file called wasisabi-netinstall.iso that silently partitions whatever the
  # baked answers name is a grenade sitting in a downloads directory.
  image.baseName = lib.mkForce (
    "wasisabi-${if offline then "offline" else "netinstall"}"
    + lib.optionalString (autotest != null) "-AUTOTEST-DESTROYS-DISKS"
  );

  isoImage = {
    volumeID = lib.mkForce (if autotest != null then "WASISABI_TEST" else "WASISABI");
    # The offline image is mostly nix store, which is exactly what zstd is
    # good at; the default is already zstd but at a level tuned for a small
    # image, and this one is not small either way.
    squashfsCompression = "zstd -Xcompression-level 15";

    # What makes an offline install possible: the closures of representative
    # systems, so the target can be built without reaching for a substituter.
    storeContents = payloads;
  };

  # The installer needs to EVALUATE wasisabi on the target, not just copy
  # store paths, so the flake sources ride along in both variants.
  system.extraDependencies =
    sources
    ++ lib.optionals offline (
      with pkgs;
      [
        # BUILD-TIME dependencies, which are a different set from the runtime
        # closures in storeContents and are the reason a first attempt at an
        # offline install failed while looking fully stocked.
        #
        # Some derivations can never be prebuilt into the image, however many
        # payloads it carries: `system-path` changes with the chosen packages,
        # and the shrunk kernel-module set changes with whatever
        # nixos-generate-config finds on the actual machine. Those get built on
        # the target, and their builders have to be here.
        #
        # This list is nixpkgs' own, from nixos/tests/installer.nix, which
        # solves exactly this problem for exactly this reason. Deriving it by
        # hand means discovering it one failed 40-minute VM run at a time.
        stdenv
        stdenvNoCC

        bintools
        brotli
        brotli.dev
        brotli.lib
        desktop-file-utils
        docbook5
        docbook_xsl_ns
        kbd.dev
        kmod.dev
        libarchive.dev
        libcap-text-verifier
        libxml2.bin
        libxslt.bin
        lndir
        nixos-rebuild-ng
        perlPackages.ConfigIniFiles
        perlPackages.FileSlurp
        perlPackages.JSON
        perlPackages.ListCompare
        perlPackages.XMLLibXML
        (python3.withPackages (p: [ p.mistune ]))
        shared-mime-info
        shellcheck-minimal
        sudo
        switch-to-configuration-ng
        texinfo
        unionfs-fuse

        # Only the out output, which is what building the NixOS udev rules
        # needs; see the comment in nixos/modules/services/hardware/udev.nix.
        systemdMinimal.out

        # Found by running an offline install and reading what it could not
        # build, rather than by reasoning: mtools is pulled in by the
        # systemd-boot installer derivation, and the other two turned up
        # underneath it.
        #
        # `.all`, NOT the bare package. Adding `mtools` ships only its default
        # output, and nix then still has to build the derivation to get the
        # other ones -- which offline means failing, while `nix path-info`
        # cheerfully shows the package "present". That is why the list above
        # spells out brotli.dev, kmod.dev, libxml2.bin and friends.
      ]
      ++ mtools.all
      ++ tzdata.all
      ++ python3Packages.mypy.all
      ++ [
        # (kept separate so the nixpkgs-derived list above stays comparable
        # with its upstream source)
        hello
      ]
    );

  environment.systemPackages = [
    installer
    pkgs.gum
    pkgs.jq
    pkgs.git
  ];

  # disko evaluates its own configuration at runtime with `import <nixpkgs>`,
  # so NIX_PATH has to point at the sources on the medium. Without this the
  # partitioning step is the first thing to fail, and only on the offline
  # image, which is the worst possible place to discover it.
  nix.nixPath = [ "nixpkgs=${nixpkgsSource}" ];
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # An offline medium that silently waits on a dead network looks like a
    # hang. Fail fast instead.
    connect-timeout = lib.mkIf offline 5;
  };

  # NetworkManager rather than the minimal ISO's wpa_supplicant: `nmtui` is a
  # text wifi picker that a person can actually use, and it is the same stack
  # the installed machine will run.
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = true;

  # Firmware, so that wifi exists on the medium that needs to reach the
  # network. See the note on the libre rule in README: these licences are
  # marked free in nixpkgs and do not trip `enforceLibre`, which is a fact
  # worth knowing rather than a loophole to lean on.
  hardware.enableRedistributableFirmware = true;

  # The layout question applies to the installer's own keyboard too: someone
  # typing a LUKS passphrase into the installer should be typing it on the
  # same layout that the initrd will present at the next boot. The installer
  # calls `loadkeys` itself once the answer is known.
  console.keyMap = lib.mkDefault "us";

  services.getty.helpLine = lib.mkForce ''

        wasi-sabi installer

        Run:  sudo wasisabi-install
        Wifi: sudo nmtui
        Docs: https://github.com/wighawag/wasisabi

        This medium installs wasisabi ${lib.substring 0 12 wasisabiRev}${lib.optionalString offline ", with no network required"}.
  '';

  # Never silently unfree, even on the installer.
  nixpkgs.config.allowUnfree = false;

  # ── the unattended path, used only by scripts/test-install-vm.sh ──
  systemd.services.wasisabi-autotest = lib.mkIf (autotest != null) {
    description = "Unattended wasisabi install (VM test)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "nix-daemon.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
    script = ''
      # Refuse on bare metal. The answers name /dev/vda, which on most
      # physical machines simply does not exist -- but "it probably will not
      # match" is luck, not a control, and this runs before any prompt.
      if ! ${lib.getExe' pkgs.systemd "systemd-detect-virt"} --quiet; then
        echo "WASISABI_AUTOTEST_REFUSED: not running in a VM"
        exit 0
      fi

      echo "WASISABI_AUTOTEST_START"
      rc=0
      ${lib.getExe' installer "wasisabi-install"} --answers ${autotest} --yes --no-reboot || rc=$?
      if [ $rc -eq 0 ]; then
        echo "WASISABI_AUTOTEST_DONE"
      else
        echo "WASISABI_AUTOTEST_FAILED rc=$rc"
        # Without this, a failure is a VM that powered off nine seconds in and
        # told you nothing at all.
        echo "=== journal ==='"
        ${lib.getExe' pkgs.systemd "journalctl"} --no-pager -b -n 200 || true
      fi
      # The harness watches for the sentinel and then for the power-off.
      ${lib.getExe' pkgs.systemd "systemctl"} poweroff
    '';
  };

  # The test harness reads the install log from the serial port. ORDER MATTERS:
  # /dev/console is the LAST console on the command line, and that is where
  # systemd sends unit output, so the serial port has to come last or the whole
  # install log goes to a VGA console nobody is reading.
  boot.kernelParams = lib.mkIf (autotest != null) [
    "console=tty0"
    "console=ttyS0,115200"
  ];

  system.stateVersion = config.system.nixos.release;
}
