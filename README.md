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
| Compositor | Hyprland | MPL-2.0 |
| Login | greetd + tuigreet | GPL/MIT |
| Bar | Waybar | MIT |
| Launcher | fuzzel | MIT |
| Notifications | mako | MIT |
| Lock / idle | hyprlock + hypridle | MIT |
| Terminal | Ghostty (or foot) | MIT |
| Shell | zsh + starship + fzf | MIT/ISC |
| Editors | Neovim + Helix (both ship) | Apache-2.0/MPL |
| Browser | Firefox (or LibreWolf/Chromium) | MPL |
| Files | Thunar (or Nautilus) | GPL |
| Passwords | KeePassXC — local-first | GPL |
| Sync | Syncthing — P2P, self-hostable (optional) | MPL |
| Media | mpv + imv | GPL/MIT |
| Theme | Catppuccin Mocha | free |

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
nix flake check                          # validate
nixos-rebuild build-vm --flake .#demo    # build the demo VM
QEMU_OPTS="-m 4096 -smp 4 -enable-kvm -vga none -device virtio-vga-gl -display sdl,gl=on" ./result/bin/run-nixos-vm
```

> The default VM has **no GPU** (QEMU std VGA → llvmpipe software rendering),
> which makes the *first* launch of a GPU-hungry app like Ghostty slow —
> shader compilation happens on the CPU. The Nixos-generated QEMU is lean and
> lacks VirGL; to get real GL, run through `./scripts/run-vm-gl.sh`, which
> patches the launch script to use your host's QEMU (which usually has VirGL
> on Linux desktops). On real hardware this never happens — real GPUs have
> real GL.
> Log in as `demo` / `demo`. Use `Alt+*` keybinds (host desktops eat `Super`).

Adopt it on a machine:

```sh
nix flake new -t github:YOUR_NAME/wasisabi ~/systems/my-laptop
# edit configuration.nix (username, hostname), drop in
# hardware-configuration.nix, pick a nixos-hardware module, then:
sudo nixos-rebuild switch --flake ~/systems/my-laptop
```

## Keybinds (defaults, `modKey = SUPER`)

> The demo VM uses `modKey = ALT` instead: your host desktop eats `Super+...`
> inside QEMU. On real hardware, leave the default.

| Keys | Action |
|---|---|
| `Super+Enter` | Terminal |
| `Super+D` | Launcher (fuzzel) |
| `Super+B` / `Super+E` | Browser / Files |
| `Super+Q` | Close window (`Super+Shift+Q` logs out) |
| `Super+H/J/K/L` | Focus (`+Shift` moves) |
| `Super+1..9` | Workspaces (`+Shift` moves window) |
| `Super+Space` / `Super+F` | Float / Fullscreen |
| `Super+Shift+S` | Screenshot region → clipboard |
| `Super+Shift+R` | Toggle screen recording |
| `Super+Shift+L` | Lock (auto-locks after 5 min idle) |

## Extending

- Add an option in `home/options.nix` (or `modules/options.nix`), gate the
  config on it, default it with `mkDefault`.
- Never use `mkForce` — that's how shared layers become hostile.
- Keep hardware knowledge out of `modules/` and `home/` — that belongs to
  the user's layer (nixos-hardware etc.).
## Session continuation

For full context (what was validated, what to fix on real hardware, lessons learned
from the build-out session, next steps in order) see [`CONTEXT.md`](CONTEXT.md).
