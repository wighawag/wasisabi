#!/usr/bin/env bash
# Run the demo VM with GPU acceleration (VirGL).
#
# The NixOS-generated run-nixos-vm script uses nix's qemu_kvm, which is built
# without GPU support (no GL → llvmpipe software rendering → GPU-hungry apps
# like Ghostty are slow on *first* launch only). This wrapper swaps in the
# host's qemu-system-x86_64, which typically has VirGL+GTK built in
# (confirmed on Debian 13 GNOME/Wayland).
#
# Usage:
#   ./scripts/run-vm-gl.sh [path/to/run-nixos-vm]
set -euo pipefail

RUNNER="${1:-}"
if [ -z "$RUNNER" ]; then
  if [ -x ./result/bin/run-nixos-vm ]; then
    RUNNER=./result/bin/run-nixos-vm
  else
    RUNNER=$(nix build --print-out-paths ".#nixosConfigurations.demo.config.system.build.vm" --no-link 2>/dev/null)/bin/run-nixos-vm || {
      echo "error: no ./result/bin/run-nixos-vm and couldn't build the vm. Run with nixos-rebuild build-vm first." >&2; exit 1; }
  fi
fi

HOSTQEMU=$(command -v qemu-system-x86_64 || true)
if [ -z "$HOSTQEMU" ]; then
  echo "error: no qemu-system-x86_64 on PATH; either install it (e.g. apt install qemu-system-x86) or just run the default run-nixos-vm (no GPU accel, but works)." >&2
  exit 1
fi
if ! "$HOSTQEMU" -device help 2>/dev/null | grep -q 'virtio-vga-gl'; then
  echo "error: $HOSTQEMU lacks virtio-vga-gl (VirGL), so this won't help. Use the default run-nixos-vm." >&2
  exit 1
fi

# Swap the nix qemu for the host qemu everywhere in the script.
sed "s|/nix/store/[a-z0-9]*-qemu[^/]*/bin/qemu-system-x86_64|$HOSTQEMU|g;
     s|/nix/store/[a-z0-9]*-qemu[^/]*/bin/qemu-img|$(command -v qemu-img || echo '/usr/bin/qemu-img')|g" \
  "$RUNNER" > /tmp/run-vm-gl-$$.sh
chmod +x /tmp/run-vm-gl-$$.sh

cd /tmp
exec env QEMU_OPTS="-m 4096 -smp 4 -enable-kvm -vga none -device virtio-vga-gl -display gtk,gl=on" /tmp/run-vm-gl-$$.sh