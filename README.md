# wasi-sabi

An opinionated, **libre-only** Wayland desktop
distributed as NixOS + home-manager **modules**, so every default is an
addressable, overridable option rather than a dotfile you must not touch.

Not a distro: the modules are the product, an ISO is just a shortcut that
installs them, and no knowledge of wasi-sabi is required to use the system —
or to leave it.

## The two rules

1. **Open source only.** Enforced at build time: the system layer asserts
   that `nixpkgs.config.allowUnfree = false` and fails the build otherwise
   (opt out with `wasisabi.enforceLibre = false`).
2. **No non-self-hostable services.** Every app works fully locally or
   against infrastructure you can run yourself. No vendor accounts by
   default.

## The stack

| Role | Choice | License |
|---|---|---|
| Compositor | niri | GPL-3.0 |
| Login | greetd + Noctalia greeter (or tuigreet) | GPL/MIT |
| Bar | Waybar | MIT |
| Launcher | fuzzel | MIT |
| Notifications | mako | MIT |
| Lock / idle | swaylock + swayidle | MIT |
| Terminal | Ghostty (or foot) | MIT |
| Shell | zsh + starship + fzf | MIT/ISC |
| Editors | Neovim + Helix (both ship) | Apache-2.0/MPL |
| Browser | Firefox (or LibreWolf/Chromium) | MPL |
| Files | Thunar (or Nautilus) | GPL |
| Passwords | KeePassXC — local-first | GPL |
| Sync | Syncthing — P2P, self-hostable (optional) | MPL |
| Media | mpv + imv | GPL/MIT |
| Theme | Catppuccin Mocha | free |
| Local AI model | llama.cpp + Gemma 4 E4B, on the CPU, on a unix socket | MIT / Apache-2.0 |
| Coding agent | pi, with wherever (a web UI for its sessions) | MIT / AGPL |
| Search | SearXNG + webveil (no account, no profile) | AGPL |
| Recall | memonaut (search your past agent sessions) | AGPL |
| Anonymous accounts | anonctl: every packet forced through Tor, fail-closed | AGPL |

## AI and privacy, on the machine

A wasisabi machine comes with an assistant that needs no account anywhere: a small open-weights model running on the CPU, private web search, and the pi coding agent wired to both, plus a web UI for its sessions on this machine only (`wherever-link` prints the address).

It also comes with three **anonymous accounts** (`anon`, `anon-john`, `anon-jane`) whose every connection the kernel forces through Tor, fail-closed: if Tor is down they have no network, never your address. Each is proven with `anonctl verify` before it is used, carries nothing of yours, and has its own agent (on the same local model, reached over a unix socket so their jail needs no exemption) and its own web UI (`sudo anon-reconcile links`).

All of it is on by default and each part is one option (`wasisabi.llm.enable`, `.search.enable`, `.agents.enable`, `.anon.enable`); the installer asks. How it fits together, what was verified and what was not: [`notes/agents.md`](notes/agents.md).

## Architecture

```
┌─ user's flake ──────────────────────────────┐
│  hardware-configuration.nix   (their disks) │
│  nixos-hardware module         (their CPU)  │
│  wasisabi.nixosModules.wasisabi  ──┐      │
│  wasisabi.homeModules.wasisabi  ──┤      │
│  their overrides / other options     │      │
└──────────────────────────────────────┼──────┘
                                       ▼
       modules/  — system layer: services, programs, zero hardware
       home/     — user layer: apps, dotfiles, keybinds, theme
       hosts/    — demo VM (proves the layers are hardware-agnostic)
       template/ — what `nix flake new -t` scaffolds for users
```

Every value in both layers uses `lib.mkDefault`, so **anything the user sets
wins**. Options are the API — extend, override, or ignore any part.

## Usage

Try it in a VM (no hardware needed):

```sh
nix flake check              # validate: evaluates every layer, runs `niri validate`,
                             # and checks the installer against the options
./scripts/run-vm-gl.sh       # build if needed, then boot it
```

On NixOS you can skip the script and use the VM directly:

```sh
nix build .#nixosConfigurations.demo.config.system.build.vm
./result/bin/run-nixos-vm
```

(`nixos-rebuild build-vm --flake .#demo` is the same thing, but `nixos-rebuild`
only exists on NixOS hosts.)

Log in as `demo` / `demo`. Use `Alt+*` keybinds (host desktops eat `Super`).

> **The VM needs a real GPU render node, and this is not negotiable.** niri
> refuses to run on a software EGL renderer (llvmpipe), so a VM with QEMU's
> default emulated VGA gives you a **black screen** rather than a slow
> desktop: niri is running fine, with a Wayland socket and working IPC, it
> just cannot render. `hosts/demo.nix` therefore asks for
> `-device virtio-vga-gl`, which gives the guest VirGL and a real
> `/dev/dri/renderD128`.
>
> The QEMU from nixpkgs supports that device, but on a **non-NixOS host** it
> cannot load the host's GL drivers (it looks in `/run/opengl-driver`, a
> NixOS-only path) and dies with `egl: render node init failed`. That is what
> `./scripts/run-vm-gl.sh` is for: it swaps in your host's QEMU, which finds
> your host's Mesa. On NixOS you do not need it.
>
> The demo VM also sets `terminal = "foot"` and `animations = false`. Ghostty
> compiles shaders on first launch, which takes about 35 seconds on a virtual
> GPU. On real hardware neither workaround is needed.
>
> **The VM disk image is disposable, and `run-vm-gl.sh` recreates it every
> run.** That is deliberate: in a NixOS build-vm the guest's `/nix/store` is an
> overlay whose upper layer is a *tmpfs*, while `/home` and `/nix/var` live on
> the qcow2 and survive a reboot. Boot the same image twice and the
> home-manager profile points at store paths that were wiped with the tmpfs,
> so activation fails with `[FAILED] Failed to start Home Manager environment`
> and you silently get a stale session. `--keep` reuses the image if you
> really want to.
>
> If the window is black through the whole boot but you can log in blind and
> get a desktop, your host is not showing QEMU's 2D console scanout. Try
> `QEMU_OPTS="-display gtk,gl=on"` or `QEMU_OPTS="-display sdl,gl=off"`.

## Installing it

### With the ISO

```sh
nix build github:wighawag/wasisabi#iso-netinstall   # small, needs a network
nix build github:wighawag/wasisabi#iso-offline      # carries everything, model included: installs with no network
# write result/iso/*.iso to a USB stick, boot it, then:
sudo wasisabi-install
```

It asks for the machine's identity (hostname, user, password, timezone, locale, **keyboard layout**), then for the disk, and then offers wasisabi's own options: greeter, shell, terminal, browser, file manager, apps, services. Skip that last part and you get the defaults, which are not written into your config and therefore keep following the project.

What it leaves behind is **an ordinary flake you own** at `/etc/nixos`: `flake.nix`, `configuration.nix`, the `hardware-configuration.nix` it generated, and a `flake.lock` pinned to exactly the revision the ISO installed. It is a git repo with one commit. Nothing reads it back, nothing manages it, and removing the two module imports leaves you with a working NixOS machine that has never heard of wasi-sabi.

There is **no live desktop on the ISO**, deliberately: niri refuses a software EGL renderer, so a graphical installer would show a black screen on exactly the machines people test on first. The installed system is the graphical thing.

The installer also runs unattended, with the same questions in a file:

```sh
wasisabi-install --answers answers.json          # install
wasisabi-install --answers answers.json --out-only ./out   # just write the flake, touch no disk
```

See [`notes/installer.md`](notes/installer.md) for how it works, what is verified and what is not.

### By hand, without the ISO

```sh
nix flake new -t github:wighawag/wasisabi ~/systems/my-laptop
# edit configuration.nix (username, hostname, stateVersion), drop in
# hardware-configuration.nix, pick a nixos-hardware module, then:
sudo nixos-rebuild switch --flake ~/systems/my-laptop
```

The installer fills in this same template, so the two paths cannot diverge.

## Adopting on an *existing* NixOS config

The template scaffolds a fresh machine, but the same two modules compose into
a config you already have — nothing about wasi-sabi requires owning the flake.

**1. Add the input**, following your nixpkgs so the module layers evaluate
against *your* pin (they are plain modules: `pkgs` comes from whichever
`nixosSystem` imports them, never from this repo's lock):

```nix
wasisabi = {
  url = "github:YOUR_NAME/wasisabi";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

**2. Import the system layer into your host's module list** — it is inert
until you opt in, so importing it everywhere is safe:

```nix
modules = [
  wasisabi.nixosModules.wasisabi   # inert until wasisabi.enable = true
  ./hosts/my-laptop
  ...
];
```

**3. Opt in per host / per user** — system defaults in the host module, the
home layer under your existing `home-manager.users.<name>`:

```nix
{
  wasisabi.enable = true;                 # system layer
  home-manager.users.me = {
    imports = [ wasisabi.homeModules.wasisabi ];
    wasisabi.enable = true;               # apps, dotfiles, keybinds
  };
}
```

Everything both layers set is `mkDefault`, so your config wins every merge,
and each `wasisabi.*` option is a seam to override any default.

Already have a `nixosConfiguration` you don't want to touch? `extendModules`
composes the layers on top of it without editing it (this is exactly how the
compose was verified against an independent fleet repo — see
[`notes/composition-verification.md`](notes/composition-verification.md) for
what was tested and the version constraints found):

```nix
myboxes.nixosConfigurations.somehost.extendModules {
  modules = [
    wasisabi.nixosModules.wasisabi
    home-manager.nixosModules.home-manager
    {
      wasisabi.enable = true;
      home-manager.users.me = {
        imports = [ wasisabi.homeModules.wasisabi ];
        wasisabi.enable = true;
      };
    }
  ];
};
```

### Version constraints (verified, not guessed)

- The **system layer** (`nixosModules.wasisabi`) composes with nixpkgs 26.05
  and home-manager release-26.05 — no skew found.
- The **home layer** currently needs home-manager **master**: it configures
  `wayland.windowManager.niri`, which landed in HM after the 26.05 branch and
  does not exist in `home-manager/release-26.05`.
- Pairing HM master with a *stable* nixpkgs pin surfaces assertion skew; the
  one hit so far is fzf (HM master wants ≥ 0.73.0 for nushell integration,
  26.05 ships 0.72.0). If you use a POSIX shell rather than nushell:
  ```nix
  programs.fzf.enableNushellIntegration = false;
  ```


## The compositor

niri is a **scrollable-tiling** compositor: windows sit in columns on an
infinite horizontal strip, and opening a window never resizes the windows you
already have. Workspaces are vertical, so the session is a grid: scroll left
and right through a workspace, up and down between workspaces.

The home-manager module runs `niri validate` on the generated config *inside
the build*, so a bad option fails `nixos-rebuild` rather than dropping you at
a black screen. See [`notes/compositor-alternatives.md`](notes/compositor-alternatives.md)
for why niri and not Sway, SwayFX or Hyprland, and what it would cost to add
one of them back.

## The keyboard layout

`wasisabi.keyboard.layout` (plus `.variant` and `.options`) is one setting for three keyboards, which is why it is an option rather than something you run once by hand.

niri deliberately keeps no copy of the layout: with an empty `xkb` block it asks systemd-localed, and localed reads `/etc/X11/xorg.conf.d/00-keyboard.conf`, which NixOS generates from `services.xserver.xkb.*` whenever a display manager is enabled. So this reaches the compositor with no X server anywhere in sight.

The other two keyboards are the text ones. The option also switches on `console.useXkbConfig`, which carries the layout to the VT **and into the initrd** -- so a LUKS passphrase chosen on a French keyboard is still typeable at the next boot. Getting that wrong produces a machine its owner cannot unlock, with nothing on screen to explain why, and it is the one thing the VM install test checks by physically typing the passphrase in the other layout.

## Keybinds (defaults, `modKey = SUPER`)

> The demo VM uses `modKey = ALT` instead: your host desktop eats `Super+...`
> inside QEMU. On real hardware, leave the default.

`Super+Shift+/` shows the full cheat sheet at any time.

| Keys | Action |
|---|---|
| `Super+Enter` | Terminal |
| `Super+D` | Launcher (fuzzel) |
| `Super+B` / `Super+E` | Browser / Files |
| `Super+Q` | Close window (`Super+Shift+Q` quits, with confirmation) |
| `Super+H/J/K/L` | Focus: left/right move between columns, up/down within one |
| `Super+Ctrl+H/J/K/L` | Move the window (Ctrl, not Shift: `Super+Shift+L` is lock) |
| `Super+1..9` | Workspaces (`+Shift` moves the column there) |
| `Super+U` / `Super+I` | Workspace down / up |
| `Super+O` | Overview |
| `Super+Space` / `Super+F` | Float / Fullscreen (`+Shift+F` maximises the column) |
| `Super+R` | Cycle column width (`Super+-` / `Super+=` for fine steps) |
| `Super+[` / `Super+]` | Pull a window into / push it out of the column |
| `Super+W` | Tabbed column display |
| `Super+C` | Centre the column |
| `Super+Shift+S` | Screenshot (interactive: region, window or screen) |
| `Print` / `Alt+Print` | Screenshot whole screen / focused window |
| `Super+Shift+R` | Toggle screen recording |
| `Super+Shift+L` | Lock (auto-locks after 5 min idle) |
| `Super+Shift+P` | Power off the monitors |
| `Super+Escape` | Release keyboard shortcuts to the focused app |

## Boot appearance

`wasisabi.splash.enable` (default true) turns on Plymouth with a Catppuccin
Mocha theme and quiets the boot: no kernel messages, no `[ OK ]` unit lines.
It does **not** hide failures. Password prompts, fsck questions and the
emergency shell still appear, so a broken boot is still visible and still
interactive. Set it to false if you would rather watch every unit start.

For the graphical splash to actually appear (rather than Plymouth falling back
to printing the boot log), your GPU driver has to be in the initrd, which is
hardware knowledge and therefore yours, not this module's:

```nix
boot.initrd.kernelModules = [ "amdgpu" ];   # or i915, nouveau, ...
```

Most `nixos-hardware` profiles already do this. `hosts/demo.nix` does it for
the VM's virtual GPU. Note that the splash is **not** verified to render inside
QEMU: there you will most likely get a quiet boot with Plymouth showing the log
instead of the themed screen.

## Extending

- Add an option in `home/options.nix` (or `modules/options.nix`), gate the
  config on it, default it with `mkDefault`.
- Never use `mkForce` — that's how shared layers become hostile.
- Keep hardware knowledge out of `modules/` and `home/` — that belongs to
  the user's layer (nixos-hardware etc.).
- Keep the look in the portable layer. The Catppuccin palette in
  `home/desktop.nix` themes the bar, launcher, notifications, lock screen and
  GTK, none of which know what compositor they run under. Only the keybinds,
  the Waybar workspaces module and the portal set are compositor-specific.

On a machine with no accelerated GPU driver, set `wasisabi.animations = false`:
under llvmpipe every animation frame is a full-screen CPU blit. The demo VM
already does this.
## Notes

- [`notes/agents.md`](notes/agents.md): the agent layer (local model, search,
  pi and wherever, anonymous accounts), its design and what is verified.
- [`notes/installer.md`](notes/installer.md) — how the ISO and installer work,
  the decisions behind them, what is verified against a real VM install and
  what is not.
- [`notes/open-items.md`](notes/open-items.md) — what has actually been verified
  against a booted VM, what has not, and the next steps in order.
- [`notes/composition-verification.md`](notes/composition-verification.md) —
  proof that the layers compose into an *existing* NixOS config (verified
  against my-boxes' telemaque), and the version constraints that came out of it.
- [`notes/compositor-alternatives.md`](notes/compositor-alternatives.md) — why
  niri and not Sway, SwayFX or Hyprland, and what swapping would cost.
