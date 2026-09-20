#!/usr/bin/env bash
# wasisabi-install: ask, partition, install, get out of the way.
#
# The questions come from installer/questions.json, which is generated from
# the option declarations in modules/options.nix and home/options.nix, so this
# script knows nothing about what wasisabi's options ARE. It renders whatever
# it is handed. Adding an option to the API adds a question here with no edit
# to this file.
#
# Everything it writes to the target goes through installer/emit.sh, which
# fills in template/ -- the same template `nix flake new` scaffolds by hand.
#
#   wasisabi-install                          interactive
#   wasisabi-install --answers answers.json   unattended, same questions
#   wasisabi-install --out-only DIR           just write the flake, touch no disk
#
set -euo pipefail

: "${WASISABI_QUESTIONS:?internal: questions.json path not baked in}"
: "${WASISABI_TEMPLATE:?internal: template path not baked in}"
: "${WASISABI_EMIT:?internal: emit.sh path not baked in}"
: "${WASISABI_LOCK:?internal: flake.lock path not baked in}"
: "${WASISABI_URL:?internal: wasisabi input url not baked in}"
: "${WASISABI_DISKO:?internal: disko layout dir not baked in}"
: "${WASISABI_NIXPKGS:?internal: nixpkgs source path not baked in}"

# disko resolves `<nixpkgs>` when it evaluates a layout. Point it at the
# sources on this medium rather than at whatever the environment happens to
# say, which in a systemd unit is nothing at all.
export NIX_PATH="nixpkgs=$WASISABI_NIXPKGS${NIX_PATH:+:$NIX_PATH}"
: "${WASISABI_STATE_VERSION:?internal: state version not baked in}"
WASISABI_OFFLINE="${WASISABI_OFFLINE:-0}"

ANSWERS_IN="" OUT_ONLY="" ASSUME_YES=0 TARGET=/mnt NO_REBOOT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --answers) ANSWERS_IN="$2"; shift 2 ;;
    --out-only) OUT_ONLY="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --no-reboot) NO_REBOOT=1; shift ;;
    --offline) WASISABI_OFFLINE=1; shift ;;
    --debug) set -x; shift ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "wasisabi-install: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

# ── output helpers ────────────────────────────────────────────────────────

# `--` before the text in every one of these: the messages are prose, and
# prose that begins with a word like "--yes" is otherwise parsed by gum as a
# flag, which turns an informational line into a failed install.
bold() { gum style --bold -- "$*"; }
note() { gum style --foreground 244 -- "$*"; }
warn() { gum style --foreground 214 -- "$*"; }
die() { gum style --foreground 196 --bold -- "error: $*" >&2; exit 1; }
heading() { echo; gum style --bold --foreground 141 -- "── $* ──"; }

# /run is tmpfs, so the LUKS passphrase never touches a real filesystem. On
# the ISO /tmp is tmpfs too, but this also runs on ordinary NixOS hosts where
# it is not, and a passphrase written to disk and then unlinked is still a
# passphrase written to disk.
WORK=$(mktemp -d -p /run 2>/dev/null || mktemp -d)
chmod 700 "$WORK"

# Set the moment the disk is handed to disko, so a later failure can say so.
DISK_TOUCHED=0

on_exit() {
  local code=$?
  # The work directory holds the LUKS passphrase while disko formats. Remove
  # it on every exit path, successful or not.
  rm -rf "$WORK"
  if [ "$code" -ne 0 ]; then
    echo
    warn "wasisabi-install stopped (exit $code)."
    if [ "$DISK_TOUCHED" = 1 ]; then
      # Every other abort path says "no disk was touched", which teaches the
      # reader that silence means safety. Past this point it does not.
      warn "${device:-the target disk} HAS ALREADY BEEN PARTITIONED AND FORMATTED."
      warn "Whatever was on it before is gone, and it is not yet a bootable system."
    fi
  fi
  exit $code
}
trap on_exit EXIT INT TERM HUP

# ── answers ───────────────────────────────────────────────────────────────

declare -A ANSWER=()
ANSWER_ORDER=()

# Whether the user walked through wasisabi's own options. Declared here
# because the --answers path never enters the interactive loop, and `set -u`
# turns an unset variable into a crash rather than an empty string.
reviewed=0

set_answer() {
  local key="$1" value="$2"
  if [ -z "${ANSWER[$key]+set}" ]; then ANSWER_ORDER+=("$key"); fi
  ANSWER[$key]="$value"
}

get_answer() { echo "${ANSWER[$1]:-}"; }

# THE INSTALLER'S OWN QUESTIONS NEED THEIR DEFAULTS WRITTEN DOWN, and this is
# the one place where "unanswered means it follows wasisabi" is NOT true.
#
# A wasisabi option left unanswered is simply absent from the generated
# config, so the machine keeps tracking the project's default -- which is the
# behaviour the summary promises. But `extra:` items are the installer's own
# (firmware, early-KMS modules): wasisabi has no opinion to fall back to, so
# silence there means the bare NixOS default. Skipping the option review used
# to leave `hardware.enableRedistributableFirmware` unset, which is `false`,
# which is a laptop that installed over wifi and then has no wifi.
apply_installer_defaults() {
  local key kind default
  while IFS=$'\t' read -r key kind default; do
    case "$key" in extra:*) ;; *) continue ;; esac
    [ -z "${ANSWER[$key]+set}" ] || continue

    if [ "$key" = "extra:initrdKernelModules" ]; then
      default=$(detect_drm_modules)
    fi
    [ -n "$default" ] || continue
    set_answer "$key" "$default"
  done < <(jq -r '.groups[].items[] | select(.emit != null) | "\(.key)\t\(.kind)\t\(.default // "")"' "$WASISABI_QUESTIONS")
}

# Which answers are secrets is read from the QUESTION DEFINITIONS, not from a
# hardcoded list of key names. The whole point of questions.nix is that new
# questions appear here without editing this script, so a new password-kind
# question must not need someone to remember to add it to a `case` before it
# stops being written to a world-readable file on the installed machine.
mapfile -t SECRET_KEYS < <(jq -r '.groups[].items[] | select(.kind == "password") | .key' "$WASISABI_QUESTIONS")

is_secret() {
  local key="$1" secret
  for secret in "${SECRET_KEYS[@]}"; do
    [ "$key" = "$secret" ] && return 0
  done
  return 1
}

answers_json() {
  local key
  {
    echo "{}"
    for key in "${ANSWER_ORDER[@]}"; do
      # Passwords never reach a file.
      is_secret "$key" && continue
      jq -n --arg k "$key" --arg v "${ANSWER[$key]}" '{($k): $v}'
    done
  } | jq -s 'add'
}

q() { jq -r "$@" "$WASISABI_QUESTIONS"; }

# ── the question loop ─────────────────────────────────────────────────────

ask_item() {
  local item="$1"
  local key kind prompt help default values
  key=$(jq -r '.key' <<<"$item")
  kind=$(jq -r '.kind' <<<"$item")
  prompt=$(jq -r '.prompt' <<<"$item")
  help=$(jq -r '.help // ""' <<<"$item")
  default=$(jq -r '.default // ""' <<<"$item")

  # Conditional questions (the LUKS passphrase only exists for the LUKS layout).
  local cond_key cond_val
  cond_key=$(jq -r '.onlyIf.key // ""' <<<"$item")
  if [ -n "$cond_key" ]; then
    cond_val=$(jq -r '.onlyIf.equals' <<<"$item")
    [ "$(get_answer "$cond_key")" = "$cond_val" ] || return 0
  fi

  echo
  bold "$prompt"
  [ -n "$help" ] && note "$help"

  case "$kind" in
    text)
      local value
      value=$(gum input --value "$default" --placeholder "$default")
      set_answer "$key" "$value"
      ;;
    password)
      local a b
      # --debug turns on `set -x`, which would otherwise trace the passphrase
      # itself to stderr, and under the unattended unit stderr is the journal
      # and the serial console. Trace nothing in here, then restore.
      local xtrace=0
      case "$-" in *x*) xtrace=1; set +x ;; esac
      while true; do
        a=$(gum input --password --placeholder "password")
        b=$(gum input --password --placeholder "again")
        [ "$a" = "$b" ] && [ -n "$a" ] && break
        warn "They did not match, or were empty. Again."
      done
      set_answer "$key" "$a"
      [ "$xtrace" = 1 ] && set -x
      ;;
    bool)
      local value
      if gum confirm --default="$([ "$default" = "true" ] && echo true || echo false)" "Enable?"; then
        value=true
      else
        value=false
      fi
      set_answer "$key" "$value"
      ;;
    enum)
      local value
      mapfile -t values < <(jq -r '.values[]' <<<"$item")
      value=$(gum choose --selected "$default" "${values[@]}")
      set_answer "$key" "$value"
      ;;
    strlist)
      local value
      value=$(gum input --value "$default" --placeholder "space separated, may be empty")
      set_answer "$key" "$value"
      ;;
    device)
      pick_device "$key"
      ;;
    *)
      die "question '$key' has kind '$kind', which this installer does not know how to ask."
      ;;
  esac
}

# ── disks ─────────────────────────────────────────────────────────────────

live_disk() {
  # The disk the installer itself booted from, so it can be called out in the
  # list rather than silently offered as a target.
  local src
  src=$(findmnt -no SOURCE /iso 2>/dev/null || true)
  [ -z "$src" ] && src=$(findmnt -no SOURCE / 2>/dev/null || true)
  [ -z "$src" ] && return 0
  lsblk -no PKNAME "$src" 2>/dev/null | head -1
}

pick_device() {
  local key="$1" live choice device
  local -a disks labelled
  live=$(live_disk || true)

  mapfile -t disks < <(lsblk -dpno NAME,SIZE,MODEL,TYPE | awk '$NF == "disk"')
  [ "${#disks[@]}" -gt 0 ] || die "no disks found to install onto."

  local line name
  for line in "${disks[@]}"; do
    name=$(awk '{print $1}' <<<"$line")
    if [ -n "$live" ] && [ "$(basename "$name")" = "$live" ]; then
      labelled+=("$line   [the live medium you booted]")
    else
      labelled+=("$line")
    fi
  done

  choice=$(gum choose "${labelled[@]}")
  device=$(awk '{print $1}' <<<"$choice")
  set_answer "$key" "$device"
}

# Checks that --yes does NOT get to skip, because they are not about being
# sure, they are about the target being the wrong device entirely.
check_device_safe() {
  local device="$1" live mounted

  [ -b "$device" ] || die "'$device' is not a block device."

  live=$(live_disk || true)
  if [ -n "$live" ] && [ "$(basename "$device")" = "$live" ]; then
    die "$device is the medium this installer is running from. Refusing."
  fi

  # Anything mounted on the target is either the running system or somebody's
  # data that is currently in use. Neither is an install target.
  mounted=$(lsblk -no MOUNTPOINTS "$device" 2>/dev/null | tr -d ' ' | grep -v '^$' || true)
  if [ -n "$mounted" ]; then
    die "$device has mounted filesystems ($(tr '\n' ' ' <<<"$mounted")). Refusing to partition a disk that is in use."
  fi
}

confirm_destruction() {
  local device="$1" typed
  echo
  warn "About to DESTROY everything on $device:"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$device" || true
  echo
  if [ "$ASSUME_YES" = 1 ]; then
    note "Proceeding without the typed confirmation (--yes)."
    return 0
  fi
  note "Type the device name ($(basename "$device")) to confirm, or anything else to abort."
  typed=$(gum input --placeholder "$(basename "$device")")
  [ "$typed" = "$(basename "$device")" ] || die "not confirmed; no disk was touched."
}

# ── the installer's own keyboard ───────────────────────────────────────────

keymap_applied=0
keymap_failed=0
apply_keymap() {
  # Switch the live console to the layout just chosen, BEFORE anything asks
  # for a LUKS passphrase. Otherwise the passphrase is typed on a US console,
  # stored, and then demanded at the next boot by an initrd running the
  # chosen layout -- an unbootable machine, created by the installer, with no
  # hint as to why.
  local layout variant
  [ "$keymap_applied" = 1 ] && return 0
  layout=$(get_answer "system:keyboard.layout")
  [ -n "$layout" ] || return 0
  variant=$(get_answer "system:keyboard.variant")
  keymap_applied=1

  # Build the argument list properly. This line previously read
  #   ckbcomp "$layout" ''${variant:+"$variant"}
  # which is Nix escaping that means nothing to bash: it passed an EMPTY
  # third argument whenever no variant was chosen, so the common case could
  # fail and fall through to the warning below.
  local -a args=("$layout")
  [ -n "$variant" ] && args+=("$variant")

  if ckbcomp "${args[@]}" 2>/dev/null | loadkeys - 2>/dev/null; then
    note "Console keyboard switched to '$layout${variant:+ ($variant)}'."
    return 0
  fi

  # Remembered rather than fatal here, because the layout is chosen BEFORE the
  # disk questions: at this point we do not yet know whether a passphrase is
  # coming. The check that matters happens before anything is partitioned.
  keymap_failed=1
  warn "Could not switch the console to '$layout'. Anything you type now uses the current layout."
}

# ── hardware detection ────────────────────────────────────────────────────

detect_drm_modules() {
  # Early KMS for the Plymouth splash. This is hardware knowledge, so it
  # belongs to the machine's own config rather than to wasisabi's modules;
  # the installer is the one place that can see the actual hardware.
  local d driver out=()
  for d in /sys/class/drm/card*/device/driver; do
    [ -e "$d" ] || continue
    driver=$(basename "$(readlink -f "$d")")
    case "$driver" in
      amdgpu|i915|xe|nouveau|radeon|virtio_gpu|ast|mgag200)
        out+=("$driver")
        ;;
    esac
  done
  printf '%s\n' "${out[@]:-}" | sort -u | tr '\n' ' ' | sed 's/ *$//'
}

# ── run ───────────────────────────────────────────────────────────────────

if [ -n "$ANSWERS_IN" ]; then
  [ -f "$ANSWERS_IN" ] || die "answers file '$ANSWERS_IN' does not exist."
  while IFS=$'\t' read -r k v; do set_answer "$k" "$v"; done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$ANSWERS_IN")
  note "Loaded $(jq 'length' "$ANSWERS_IN") answers from $ANSWERS_IN"
else
  clear
  gum style --border rounded --padding "1 3" --border-foreground 141 \
    "$(gum style --bold 'wasi-sabi')" \
    "an opinionated, libre-only Wayland desktop" \
    "" \
    "This asks for your machine's identity, then for wasisabi's own" \
    "options, and writes an ordinary NixOS flake to /etc/nixos that" \
    "you own and can edit or abandon afterwards."

  reviewed=0
  ngroups=$(q '.groups | length')
  for gi in $(seq 0 $((ngroups - 1))); do
    title=$(q ".groups[$gi].title")
    essential=$(q ".groups[$gi].essential // false")

    # Identity and disks are not optional. wasisabi's own options are, and
    # being asked twenty questions you have no opinion about is a bad first
    # impression -- so offer the defaults once, in one go, and let anyone who
    # does care say so. Options left at their default are NOT written into the
    # generated config, so the machine keeps tracking wasisabi's defaults
    # rather than freezing today's values into a file.
    if [ "$essential" != "true" ] && [ "$reviewed" = 0 ]; then
      heading "wasisabi's own options"
      note "$(q '[.groups[] | select(.essential != true) | .items[] | select(.emit != null)] | length') options control the desktop itself: greeter, shell, terminal, browser, apps, services."
      note "The defaults are the project's opinion and are all documented in modules/options.nix."
      if gum confirm --default=false "Review them one by one?"; then
        reviewed=1
      else
        note "Keeping the defaults. Nothing is written for them, so they follow wasisabi as it changes."
        break
      fi
    fi

    heading "$title"
    nitems=$(q ".groups[$gi].items | length")
    for ii in $(seq 0 $((nitems - 1))); do
      item=$(q -c ".groups[$gi].items[$ii]")

      # Offer the detected GPU driver as the default rather than an empty box.
      if [ "$(jq -r '.key' <<<"$item")" = "extra:initrdKernelModules" ]; then
        item=$(jq --arg d "$(detect_drm_modules)" '.default = $d' <<<"$item")
      fi

      ask_item "$item"
    done

    # As soon as the layout is known, make it the layout in use.
    apply_keymap
  done
fi

# Both paths: whatever the installer owns and nobody answered gets its
# documented default, explicitly, rather than falling through to NixOS's.
apply_installer_defaults

# ── validate ──────────────────────────────────────────────────────────────

hostname=$(get_answer "identity:hostname")
username=$(get_answer "identity:username")
layout=$(get_answer "disk:layout")
device=$(get_answer "disk:device")

# Mirrors the assertion in nixpkgs' networking module, so an invalid name
# fails HERE rather than after the disk has been partitioned.
[[ "$hostname" =~ ^[[:alnum:]]([[:alnum:]_-]{0,61}[[:alnum:]])?$ ]] || die "'$hostname' is not a valid hostname."
[[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "'$username' is not a valid Linux username."

# Names that already exist on any NixOS system: declaring them as a normal
# user is an evaluation error, which without this check arrives after the wipe.
case "$username" in
  root|nobody|messagebus|systemd-*|nixbld*|greeter|nscd|sshd|polkituser)
    die "'$username' is a system account name; pick another."
    ;;
esac

# An empty password is not a password. The interactive path already refuses
# one; an answers file that omits the key must not quietly produce a machine
# whose only account cannot be logged into (or worse, can be without one).
if [ -z "$OUT_ONLY" ] && [ -z "$(get_answer "identity:password")" ]; then
  die "no password was given for '$username'. Add identity:password to the answers file."
fi

[ -n "$OUT_ONLY" ] || [ -n "$layout" ] || die "no disk layout chosen."

# The encrypted case, checked before any disk is touched: a passphrase typed
# on a console whose layout could not be set will not be the passphrase the
# initrd asks for, and the result is a machine nobody can unlock.
if [ -z "$OUT_ONLY" ] && [ "$layout" = "luks" ] && [ "$keymap_failed" = 1 ]; then
  die "the console could not be switched to the '$(get_answer "system:keyboard.layout")' layout, so an encrypted install would take its passphrase on the wrong keyboard. Nothing was touched."
fi

if [ -z "$OUT_ONLY" ]; then
  [ "$(id -u)" = 0 ] || die "installing needs root. Try: sudo wasisabi-install"
  [ -d /sys/firmware/efi ] || die "this machine did not boot in UEFI mode. wasisabi's shipped layouts are UEFI-only; use the manual layout for BIOS."
fi

# ── emit the flake ────────────────────────────────────────────────────────

answers_json > "$WORK/answers.json"

if [ -n "$OUT_ONLY" ]; then
  bash "$WASISABI_EMIT" \
    --questions "$WASISABI_QUESTIONS" --answers "$WORK/answers.json" \
    --template "$WASISABI_TEMPLATE" --out "$OUT_ONLY" \
    --state-version "$WASISABI_STATE_VERSION" --wasisabi-url "$WASISABI_URL"
  # install, not cp: the lock comes from the store at mode 0444, and a plain
  # copy leaves a read-only file that a second run cannot overwrite and that
  # `nix flake update` in the resulting tree cannot rewrite.
  install -m 0644 "$WASISABI_LOCK" "$OUT_ONLY/flake.lock"
  bold "Wrote the flake to $OUT_ONLY. No disk was touched."
  exit 0
fi

# ── summary and the point of no return ────────────────────────────────────

heading "Summary"
printf '  %-16s %s\n' \
  "hostname" "$hostname" \
  "user" "$username" \
  "disk" "${device:-(already mounted at $TARGET)}" \
  "layout" "$layout" \
  "packages from" "$([ "$WASISABI_OFFLINE" = 1 ] && echo "this medium, offline" || echo "cache.nixos.org, over the network")"
echo
# Only true when the options were NOT reviewed. Walking through them records
# what you chose, including choices that match today's default, and recorded
# values are exactly the ones that stop tracking the project.
if [ "$reviewed" = 0 ] && [ -z "$ANSWERS_IN" ]; then
  note "Options you did not set are left out of the config, so they keep following wasisabi."
fi
jq -r 'to_entries[] | select(.key | startswith("identity:") or startswith("disk:") | not) | "  \(.key | sub("^[a-z]+:"; "")) = \(.value)"' "$WORK/answers.json" 2>/dev/null || true

if [ "$ASSUME_YES" != 1 ]; then
  gum confirm "Install now?" || die "aborted; no disk was touched."
fi

# ── partition ─────────────────────────────────────────────────────────────

if [ "$layout" = "manual" ]; then
  mountpoint -q "$TARGET" || die "layout is 'manual' but nothing is mounted at $TARGET."
  note "Manual layout: using the filesystems already mounted at $TARGET."
else
  check_device_safe "$device"
  confirm_destruction "$device"

  # Quoted because the comma-separated mode is one argument to disko, not
  # three array elements (shellcheck SC2054 is right to ask).
  #
  # --root-mountpoint, because disko otherwise mounts at its own default of
  # /mnt regardless of --target: the disk would be wiped and formatted and the
  # install would then abort saying nothing is mounted where it expected.
  disko_args=(
    --mode "destroy,format,mount"
    --yes-wipe-all-disks
    --root-mountpoint "$TARGET"
    --argstr device "$device"
  )
  if [ "$layout" = "luks" ]; then
    passfile="$WORK/luks.key"
    (umask 077; printf '%s' "$(get_answer "disk:passphrase")" > "$passfile")
    [ -s "$passfile" ] || die "the LUKS layout needs a passphrase."
    disko_args+=(--argstr passphraseFile "$passfile")
  fi

  heading "Partitioning $device"
  DISK_TOUCHED=1
  disko "${disko_args[@]}" "$WASISABI_DISKO/$layout.nix"
fi

mountpoint -q "$TARGET" || die "nothing is mounted at $TARGET after partitioning."

# ── hardware configuration ────────────────────────────────────────────────

heading "Detecting hardware"
nixos-generate-config --root "$TARGET"
# Its configuration.nix is a scaffold we are about to replace with the real
# one; hardware-configuration.nix is the part worth keeping.
rm -f "$TARGET/etc/nixos/configuration.nix"

# ── write the flake ───────────────────────────────────────────────────────

heading "Writing /etc/nixos"
bash "$WASISABI_EMIT" \
  --questions "$WASISABI_QUESTIONS" --answers "$WORK/answers.json" \
  --template "$WASISABI_TEMPLATE" --out "$WORK/flake" \
  --state-version "$WASISABI_STATE_VERSION" --wasisabi-url "$WASISABI_URL"

install -m 0644 "$WASISABI_LOCK" "$WORK/flake/flake.lock"
install -m 0644 \
  "$WORK/flake/flake.nix" \
  "$WORK/flake/configuration.nix" \
  "$WORK/flake/flake.lock" \
  -t "$TARGET/etc/nixos/"

# The pinned lock is the difference between installing what was tested and
# installing whatever is current. If it did not land, stop now rather than
# letting nix quietly resolve something else.
[ -f "$TARGET/etc/nixos/flake.lock" ] || die "internal: the pinned flake.lock did not reach $TARGET/etc/nixos."

# A record of what was answered. Nothing reads it back: it is there so that
# "how was this machine installed" has an answer a year from now.
jq '.' "$WORK/answers.json" > "$TARGET/etc/nixos/installer-answers.json"
chmod 0644 "$TARGET/etc/nixos/installer-answers.json"

# git first, and committed, so that the flake is a clean tree from the moment
# it exists -- and because an uncommitted git repo would hide these very files
# from nix, which does not see untracked files in a git tree.
if [ ! -d "$TARGET/etc/nixos/.git" ]; then
  git -C "$TARGET/etc/nixos" init -q -b main
  git -C "$TARGET/etc/nixos" add -A
  git -C "$TARGET/etc/nixos" \
    -c user.name=wasisabi-install -c user.email=installer@localhost \
    commit -q -m "Install $hostname with wasisabi

Generated by wasisabi-install from template/ plus the answers in
installer-answers.json. This is an ordinary NixOS flake: edit it, rebuild with
  sudo nixos-rebuild switch --flake /etc/nixos#$hostname
or walk away from wasisabi entirely by removing the module imports."
fi

# ── install ───────────────────────────────────────────────────────────────

heading "Building and installing the system"
note "This is the long part. It is building your actual configuration, not unpacking an image."

# TWO ROUTES TO THE SAME PLACE, because "offline" is not a flag nixos-install
# can pass on.
#
# Networked: `nixos-install --flake` builds with `--store /mnt`, so everything
# it downloads lands straight on the target disk. That matters, because the
# ISO's own /nix/store is a squashfs with a tmpfs overlay -- building there
# would download several gigabytes into RAM.
#
# Offline: nix needs `--offline` to resolve a locked github input from a store
# path instead of fetching the tarball, and `nixos-install` accepts neither
# that flag nor an equivalent `--option` (there is no `offline` setting). So
# the toplevel is built explicitly here, where the flag can be given, and
# handed over as a prebuilt system. Everything it needs is already on the
# medium, so this builds only the handful of tiny derivations that depend on
# the answers, and RAM is not at risk.
if [ "$WASISABI_OFFLINE" = 1 ]; then
  note "Building from this medium, with the network explicitly disabled."
  if ! toplevel=$(nix build --offline --no-link --print-out-paths --no-update-lock-file \
      "path:$TARGET/etc/nixos#nixosConfigurations.$hostname.config.system.build.toplevel"); then
    warn "Could not build the system from this medium."
    toplevel=""
  fi
  install_args=(--root "$TARGET" --system "$toplevel" --no-root-password)
  [ -n "$toplevel" ] || install_args=()
else
  install_args=(--root "$TARGET" --flake "path:$TARGET/etc/nixos#$hostname" --no-root-password --no-update-lock-file)
fi

if [ "${#install_args[@]}" -eq 0 ] || ! nixos-install "${install_args[@]}"; then
  # The most likely way for this to fail is the pinned lock being rejected,
  # and "requires lock file changes" does not say WHICH changes. Ask nix, on a
  # scratch copy so nothing on the target is modified, and show the diff.
  warn "nixos-install failed. Checking whether the pinned lock is the reason."
  if cp -r "$TARGET/etc/nixos" "$WORK/lockdiag" 2>/dev/null; then
    chmod -R u+w "$WORK/lockdiag"
    rm -rf "$WORK/lockdiag/.git"
    if (cd "$WORK/lockdiag" && nix flake lock --extra-experimental-features 'nix-command flakes' 2>&1 | head -20); then
      echo "--- what nix wanted to change in flake.lock ---"
      diff <(jq -S . "$TARGET/etc/nixos/flake.lock") <(jq -S . "$WORK/lockdiag/flake.lock") | head -60 || true
      echo "--- end ---"
    fi
  fi
  die "the system could not be built. Nothing was written to the bootloader."
fi

# ── password ──────────────────────────────────────────────────────────────

heading "Setting the password"
# Straight into the target's /etc/shadow, so no password material is written
# into the flake, which therefore stays publishable.
#
# chpasswd is resolved out of the TARGET's store rather than called by name:
# a freshly installed system has no `chpasswd` on its system path (shadow is
# there as a dependency, not as an installed program), so calling it by name
# gets "command not found" after a perfectly good install.
set_target_password() {
  local user="$1" secret="$2" chpasswd

  local xtrace=0
  case "$-" in *x*) xtrace=1; set +x ;; esac

  chpasswd=$(find "$TARGET/nix/store" -maxdepth 3 -type f -path '*-shadow-*/bin/chpasswd' 2>/dev/null | head -1)
  if [ -z "$chpasswd" ]; then
    [ "$xtrace" = 1 ] && set -x
    return 1
  fi

  printf '%s:%s\n' "$user" "$secret" | nixos-enter --root "$TARGET" -c "${chpasswd#"$TARGET"}"
  local rc=$?
  [ "$xtrace" = 1 ] && set -x
  return $rc
}

if set_target_password "$username" "$(get_answer "identity:password")"; then
  note "Password set for $username."
else
  # NOT "log in as root": the install ran with --no-root-password and the
  # template sets none, so root is locked and no account on that machine has
  # a usable password. The only way in is from this medium.
  warn "Could not set the password for $username."
  warn "The system IS installed but NOBODY CAN LOG INTO IT YET, including root."
  warn "Fix it from this installer medium, before rebooting:"
  warn "  mount /dev/... $TARGET   # the root filesystem you just installed to"
  warn "  nixos-enter --root $TARGET -c 'passwd $username'"
fi

# Make the flake editable by its owner without sudo. Read the ids out of the
# target's own passwd rather than asking the running system, whose accounts
# have nothing to do with the installed machine's.
ids=$(awk -F: -v u="$username" '$1 == u { print $3":"$4 }' "$TARGET/etc/passwd" || true)
if [ -n "$ids" ]; then
  chown -R "$ids" "$TARGET/etc/nixos"
else
  warn "could not find $username in the installed passwd; /etc/nixos stays root-owned (edit with sudo)."
fi

# ── done ──────────────────────────────────────────────────────────────────

heading "Done"
gum style --border rounded --padding "1 3" --border-foreground 141 \
  "$(gum style --bold "$hostname is installed.")" \
  "" \
  "Log in as $username." \
  "Your config is /etc/nixos, a normal flake you own:" \
  "  sudo nixos-rebuild switch --flake /etc/nixos#$hostname" \
  "" \
  "Options: nixos-option wasisabi, or modules/options.nix upstream."

# A machine-readable line, so an automated install can be checked for success
# rather than for the absence of an error message.
echo "WASISABI_INSTALL_OK host=$hostname user=$username layout=$layout"

if [ "$NO_REBOOT" = 1 ]; then
  note "Leaving the machine running (--no-reboot)."
elif [ "$ASSUME_YES" = 1 ]; then
  note "Rebooting now."
  systemctl reboot
elif gum confirm "Reboot now?"; then
  systemctl reboot
fi
