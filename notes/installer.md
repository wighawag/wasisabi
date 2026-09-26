# The installer

What was built, what was decided and why, what is verified, and what is not. Written 2026-09-20.

## What exists now

`wasisabi-install` is a text installer that asks for a machine's identity and then for wasisabi's own options, partitions a disk, and writes an ordinary NixOS flake to `/etc/nixos` before installing it. It ships on two ISO variants (`netinstall`, `offline`) plus purpose-built unattended variants used only by the VM test.

```
nix build .#iso-netinstall     # small, needs a network
nix build .#iso-offline        # carries the packages too
nix build .#installer          # the installer alone, runnable on any NixOS host
./scripts/test-install-vm.sh   # install into a VM and check the result
```

The installer's own emit step is runnable without a disk anywhere near it, which is what makes it testable: `wasisabi-install --answers answers.json --out-only DIR` writes the flake it would install and touches nothing else.

## The decisions

**A text installer, not a graphical one.** niri refuses to run on a software EGL renderer, so a graphical installer ISO shows a black screen on exactly the machines people try first (QEMU without `virtio-vga-gl`, anything with no render node) while niri runs perfectly in the background. A text installer that always works beats a graphical one that fails illegibly. The ISO therefore ships no live desktop at all: the installed system is the graphical thing, the medium that installs it is not.

**One implementation, two entry points.** The interactive TUI and the unattended answer file are the same code path: the TUI writes answers, `--answers` reads them. There is no second, less-tested code path for automation, and the VM test exercises the same installer a person runs.

**The questions are generated from the option declarations.** `installer/questions.nix` walks `modules/options.nix` and `home/options.nix` with `lib.evalModules` and reads each option's type, allowed values, default and description. An enum becomes a picker whose values are the enum's values; a bool becomes a yes/no; the help text is the option's own documentation. Adding an enum value or rewording a description changes the installer with nothing to keep in sync.

`installer/plan.nix` holds the only hand-written half: ordering, grouping, and the installer's own non-option questions (hostname, user, password, disk). It must classify **every** declared option as either asked or skipped-with-a-reason, and `questions.nix` throws otherwise. That throw is a flake check, so adding an option to the API without deciding its installer story fails the build. This is the anti-drift guarantee, and it is the reason the installer does not contain a list of wasisabi's options anywhere.

**Options left at their default are not written to the config.** The installer offers to skip its twenty-odd option questions in one go, and anything not explicitly answered is simply absent from the generated `configuration.nix`. So a machine installed with the defaults keeps tracking wasisabi's defaults as they change, rather than freezing today's values into a file the owner never chose. What you answered is written; what you did not is left alone. The `emit-roundtrip` check asserts both halves.

**The emitter contains no configuration text.** Everything it writes comes from `template/` (the same template `nix flake new -t` scaffolds by hand) plus the answers. It substitutes the placeholders and splices the answers between `# >>> wasisabi:system` and `# <<< wasisabi:home` markers. There is no second copy of the config to drift, and the `emit-roundtrip` check runs the real emitter and then evaluates the result as a real NixOS configuration, asserting that each answer actually took effect.

**Partitioning is disko, at install time only.** Two shipped whole-disk layouts (`plain`, `luks`) and a `manual` path that uses whatever is already mounted at `/mnt`. The installed system does **not** import disko or depend on it: `nixos-generate-config` writes the real UUIDs, and for LUKS it writes the `boot.initrd.luks.devices` entry, so the machine unlocks and boots with no trace of how it was partitioned. No swap partition is created, because zram is on by default; hibernation needs one and is therefore a manual-layout job.

**No password material in the flake.** The password is set straight into the target's `/etc/shadow` with `chpasswd`, exactly as any other distro does, so the generated flake can be pushed to a public repository as it stands. The generated `configuration.nix` says so, and says how to make it declarative with `hashedPasswordFile` pointing outside the flake.

**The lock is pinned, not resolved on the target.** `installer/lock.nix` synthesises the user's `flake.lock` from this repo's own, so the machine you booted is the machine you get. Without this, first boot would resolve `nixos-unstable` to whatever is current that day and rebuild the world from a revision nobody tested, and an offline install could not resolve anything at all. `nixos-install` is called with `--no-update-lock-file`, so a lock that does not match fails the install loudly instead of silently installing something else.

A committed tree pins `github:wighawag/wasisabi` at that revision. An **uncommitted** tree pins a `path:` into the medium's own store instead, so a development ISO reproduces the exact tree it was built from, and the generated flake says so in its input URL rather than pretending to be a release. That second mode is also the mechanism that would serve a private repository. One caveat on it: a `path:/nix/store/...` pin is not a GC root on the installed machine, so `nix-collect-garbage -d` there can delete the source the flake points at and leave a config that no longer evaluates. Survivable (repoint the input at a real revision), and another reason development media are development media.

## The keyboard decision, and why it is an option

There was no keyboard option in wasisabi, and the obvious move was to have the installer run `localectl set-x11-keymap`. That is wrong on NixOS twice over: it is imperative state no rebuild can reproduce, and NixOS itself manages the file localed reads.

The mechanism was verified rather than assumed. greetd turns on `services.displayManager.enable`, which turns on nixpkgs' `services.graphical-desktop`, which renders `services.xserver.xkb.*` into `/etc/X11/xorg.conf.d/00-keyboard.conf`. systemd-localed reads that file, and niri asks localed because `home/desktop.nix` deliberately leaves its own xkb block empty. So `wasisabi.keyboard.layout` reaches the compositor declaratively with no X server anywhere and no change to the niri config.

The option also sets `console.useXkbConfig`, and that half matters more than the desktop half: it carries the layout to the VT and **into the initrd**. Choose a French layout, set a LUKS passphrase containing an `a`, leave the console on US, and the machine is unbootable by its owner with no indication why. The VM test covers this specifically: it unlocks the encrypted install by sending the physical keys that spell the passphrase *on a French keyboard*, so if the layout ever stops reaching the initrd the test hangs at the prompt rather than quietly passing.

## Firmware and the libre rule

The ISO enables `hardware.enableRedistributableFirmware`, because without it a great many laptops have no wifi and cannot reach the network they are installing from. This does **not** trip the `enforceLibre` assertion: nixpkgs marks these licences `free = true` (verified against the pin), so `allowUnfree = false` never sees them. That is a fact worth knowing rather than a loophole to lean on, and the installer asks about it explicitly for the installed system instead of deciding silently.

## Verified, and how

Against real VM installs, not evaluation:

- **A plain install, end to end.** Boot the ISO, partition `/dev/vda`, generate the hardware config, write the flake, build and install the system, install the bootloader, set the password. Reported by a machine-readable sentinel, then the installed disk boots on its own.
- **A LUKS install, end to end**, including unlocking at the next boot with French-layout keystrokes, which is simultaneously the encryption test and the keyboard-to-initrd test.

Be precise about the last step of each of those, because the automated assertion is weaker than the claim: the harness checks that the screen is not a single flat colour, which a kernel panic would also satisfy. That **a login screen** was on it was established by a human looking at the screenshots in `.vm/install-test/`. Strengthening that check is worth doing and has not been done.
- **An offline install, end to end, with no network device attached to the VM at all** (`-nic none`, so a medium that quietly reached for cache.nixos.org could not pass). 106 seconds from boot to installed, then boots to its login screen.
- **The pinned lock is accepted verbatim.** Verified twice: `nix flake lock` on a freshly emitted flake reports no changes, and the whole generated flake evaluates `--offline` with a cold fetcher cache from a read-only lock.
- **`niri validate` actually runs in `nix flake check`.** It did not before: `flake check` only evaluates `nixosConfigurations` to a `.drv`, so the niri config derivation was never built and the validation the compositor was chosen for never ran. It is now a check.

## Sizes

| Medium | Size | Needs |
|---|---|---|
| `iso-netinstall` | 1.5G | a network |
| `iso-offline` | 8.5G | nothing (the local model's 4.2 GB included) |

The offline image carries four payload systems, generated so that every value of every enum appears in at least one of them (`nix build .#checks.x86_64-linux.payload-coverage` prints the coverage), plus the build-time inputs for the handful of derivations that can never be prebuilt.

## Known gaps in the installer itself

- **The interactive path has no automated test.** The unattended `--answers` route is exercised by every VM run, but the TUI branch, the review-the-options prompt and the console keymap switch are only ever exercised by hand. A review caught two bugs living in exactly that gap (a Nix escape that made `ckbcomp` take an empty argument, and declining the option review leaving firmware unset); both are fixed, and the lesson is that the untested branch is where the bugs were.
- **`--yes` skips the typed device confirmation**, because the automated test needs it to. It no longer skips the checks that matter: refusing the live medium and refusing any disk with mounted filesystems are not confirmations and cannot be bypassed.

## Not verified

- **The graphical session after login.** niri needs a real render node, and the machine this was built on has no `/run/opengl-driver`, so QEMU cannot give the guest GL. The test verifies boot-to-login-screen with the text greeter; verifying the session itself needs a GL-capable host and `./scripts/run-vm-gl.sh`. The harness detects host GL and says which of the two it is doing rather than quietly checking the weaker thing.
- **Real hardware.** Everything here is QEMU. Wifi, the firmware question, nixos-hardware profiles and the Plymouth splash are all untested on a physical machine.
- **Stages 3 and 4 of the harness** (inspect the installed filesystem from outside, and rebuild `/etc/nixos` offline to prove it reproduces the installed system byte for byte) are stubbed. Stage 4 is the strongest available evidence that the generated flake is real rather than decorative, and it is the obvious next thing to write.

## Traps hit while building this, worth not re-learning

- **`nix flake check` does not build `nixosConfigurations`.** It evaluates them. Anything that only runs at build time (like `niri validate`) runs never, unless it is a `checks` output.
- **Flake lock node names are arbitrary.** Nix disambiguates duplicates by appending `_2`, so in this repo's lock the root's nixpkgs was `nixpkgs_2` while plain `nixpkgs` belonged to nixos-hardware. Hardcoding the obvious names silently pinned installed machines to a *different* nixpkgs revision than the one that was built and tested. `installer/lock.nix` now resolves every node through the root's actual input map.
- **A lock that shares a node between two inputs is stale to nix** even when both would resolve to the same revision. The template collapses the graph with `follows` so that the shape nix wants is the shape it gets.
- **`console=ttyS0 console=tty0` sends unit output to the VGA console**, because `/dev/console` is the *last* console on the command line. The serial port has to come last or an automated install logs to a screen nobody is reading.
- **`writeShellApplication` shellchecks its own wrapper**, and a systemd unit inherits no useful `PATH`: `exec bash script.sh` died with exit 127 eight milliseconds in. Interpreters and tools have to be absolute or in `runtimeInputs`.
- **A freshly installed system has no `chpasswd` on its system path.** shadow is in the closure as a dependency, not as an installed program, so the installer resolves it from the target's own store.
- **`nixos-generate-config` puts the bootloader in its `configuration.nix`**, which the installer discards. Nothing else sets one, so the template must. This was invisible to every check because the roundtrip check's stub hardware file happened to supply it, and it only surfaced at the very last step of a real install.
- **`nixos-install` cannot be made offline.** It forwards `--option`, but there is no `offline` nix *setting* (only the flag), so a locked `github:` input gets fetched as a tarball rather than resolved from the store path sitting right there. The offline path therefore builds the toplevel itself with `nix build --offline` and hands it over with `--system`. The networked path keeps `--flake`, because that builds with `--store /mnt` and so downloads onto the disk rather than into the ISO's tmpfs-backed store.
- **A runtime closure is not a build closure.** An offline medium can contain the entire desktop and still fail, because `system-path` changes with the chosen packages and the shrunk kernel-module set changes with whatever `nixos-generate-config` finds. Those are built on the target and their builders must be shipped: the list in `hosts/iso.nix` is nixpkgs' own from `nixos/tests/installer.nix`.
- **Shipping a package ships one output.** `system.extraDependencies = [ mtools ]` puts mtools in the image, `nix path-info` confirms it is "there", and the install still fails to build mtools because it wanted a different output. Use `pkg.all`. This is why the nixpkgs list spells out `brotli.dev`, `kmod.dev`, `libxml2.bin` and friends.
- **A payload that differs by one option is not a payload.** The systemd-boot installer is a generated Python script that embeds its settings and is type-checked with mypy at build time. The payload systems set `systemd-boot.enable` but not `canTouchEfiVariables`, so the target had to rebuild that script, which dragged in python, mypy and its source tarballs. Payloads must match `template/configuration.nix` exactly, or they are not covering anything.
