# The installer's question plan: what gets asked, in what order, under which
# heading, and -- for anything NOT asked -- why not.
#
# This file is the only hand-maintained half of the installer's questions. The
# other half (prompt text, type, allowed values, default) is read out of the
# option declarations themselves by ./questions.nix, so an option and its
# question cannot describe different things.
#
# THE COVERAGE RULE. Every leaf option in modules/options.nix and
# home/options.nix must appear exactly once, either in a group below or in
# `skip` with a reason. questions.nix throws otherwise, and that throw is a
# flake check, so adding an option to the API without deciding its installer
# story fails the build rather than silently producing an installer that
# cannot reach half the system.
#
# Keys are layer-qualified: "system:greetd.greeter", "home:terminal". Items
# with a `kind` are the installer's own questions (identity, disks), which are
# not wasisabi options and therefore have nothing to read a declaration from.

{
  groups = [
    {
      title = "Machine identity";
      # Essential groups are always asked. The rest are wasisabi's own
      # opinions, which the installer offers to skip in one go: see install.sh.
      essential = true;
      items = [
        {
          key = "identity:hostname";
          kind = "text";
          prompt = "Hostname";
          default = "wasisabi";
          help = "The machine's name on the network, and the name of its nixosConfiguration in the flake this installer writes.";
          validate = "hostname";
        }
        {
          key = "identity:username";
          kind = "text";
          prompt = "Username";
          default = "";
          help = "Your login account. It goes in the wheel group, so it can sudo, and in networkmanager and video.";
          validate = "username";
        }
        {
          key = "identity:password";
          kind = "password";
          prompt = "Password for that account";
          help = "Set in the installed system with chpasswd, exactly as on any other distro. It is deliberately NOT written into the flake, so the flake stays publishable.";
        }
        { option = "system:timeZone"; }
        { option = "system:locale"; }
        { option = "system:keyboard.layout"; }
        { option = "system:keyboard.variant"; }
        { option = "system:keyboard.options"; }
      ];
    }

    {
      title = "Disk";
      essential = true;
      items = [
        {
          key = "disk:device";
          kind = "device";
          prompt = "Install to which disk";
          help = "EVERYTHING ON THE CHOSEN DISK IS DESTROYED. The installer lists what it found and asks you to type the device name back before it touches anything.";
        }
        {
          key = "disk:layout";
          kind = "enum";
          prompt = "Disk layout";
          default = "plain";
          values = [ "plain" "luks" "manual" ];
          help = "plain: GPT, a 512M EFI partition, ext4 root. luks: the same with the root inside LUKS2, unlocked by passphrase at boot. manual: you already partitioned and mounted the target at /mnt yourself, and the installer will not touch any disk. No swap partition is made in either automatic layout, because zram is on by default; hibernation needs one and is therefore a manual-layout job.";
        }
        {
          key = "disk:passphrase";
          kind = "password";
          prompt = "LUKS passphrase";
          help = "Asked twice. Type it on the keyboard layout you chose above: that layout is carried into the initrd, which is the keyboard this passphrase will be typed on at every boot.";
          onlyIf = { key = "disk:layout"; equals = "luks"; };
        }
      ];
    }

    {
      title = "The libre rule";
      items = [
        { option = "system:enforceLibre"; }
        {
          key = "extra:firmware";
          kind = "bool";
          prompt = "Install redistributable firmware blobs";
          default = "true";
          help = "Vendor firmware for wifi, bluetooth and some GPUs. It is binary-only, so it sits at the edge of the libre rule, but it does NOT trip the enforceLibre assertion: nixpkgs marks these licences free = true. Without it a great many laptops have no wifi at all. Says yes by default because the alternative is a machine that cannot reach the network it was just installed from.";
          emit = { attr = "hardware.enableRedistributableFirmware"; block = "system"; };
        }
      ];
    }

    {
      title = "Login and boot";
      items = [
        { option = "system:greetd.enable"; }
        { option = "system:greetd.greeter"; }
        { option = "system:splash.enable"; }
        {
          key = "extra:initrdKernelModules";
          kind = "strlist";
          prompt = "Early KMS driver for the boot splash";
          default = "";
          help = "The GPU driver loaded in the initrd, so Plymouth owns the screen from the start instead of falling back to printing the boot log. The installer fills in what it detects on this machine (amdgpu, i915, nouveau, virtio_gpu). This is hardware knowledge, which is why it lands in your config rather than in wasisabi's modules. Leave it empty if you do not want early KMS.";
          emit = { attr = "boot.initrd.kernelModules"; block = "system"; };
        }
      ];
    }

    {
      title = "Hardware services";
      items = [
        { option = "system:zram.enable"; }
        { option = "system:bluetooth.enable"; }
        { option = "system:cellular.enable"; }
        { option = "system:printing.enable"; }
      ];
    }

    {
      title = "Network services";
      items = [
        { option = "system:tor.enable"; }
      ];
    }

    {
      title = "Desktop";
      items = [
        { option = "home:shell"; }
        { option = "home:modKey"; }
        { option = "home:animations"; }
      ];
    }

    {
      title = "Programs";
      items = [
        { option = "home:terminal"; }
        { option = "home:editor"; }
        { option = "home:browser"; }
        { option = "home:fileManager"; }
      ];
    }

    {
      title = "Extra apps";
      items = [
        { option = "home:apps.media"; }
        { option = "home:apps.office"; }
        { option = "home:apps.email"; }
        { option = "home:apps.passwords"; }
        { option = "home:apps.syncthing"; }
      ];
    }
  ];

  skip = {
    "system:enable" = "The installer is installing wasisabi; asking whether to enable it is not a question.";
    "home:enable" = "Same: the home layer is the point of installing, and the generated configuration.nix shows the line so it can be removed by hand later.";
  };
}
