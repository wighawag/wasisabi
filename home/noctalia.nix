{ lib, pkgs, config, noctaliaSrc, ... }:

# Noctalia: one shell owning bar, dock, launcher, control center,
# notifications, wallpaper, lock screen, OSDs and clipboard history, instead of
# the five single-purpose daemons in desktop.nix. MIT, native Wayland + OpenGL
# ES, no Qt or GTK dependency.
#
# BUILT FROM SOURCE, NOT CONSUMED AS A FLAKE, and that is a deliberate choice
# with a concrete payoff: upstream's flake pins its own nixos-unstable, so
# taking their outputs drags a SECOND nixpkgs into every consumer's closure and
# makes the shell's GL stack disagree with the compositor's. Their
# `nix/package.nix` is a plain callPackage file, so building it against OUR
# pkgs sidesteps that entirely and keeps one nixpkgs per machine. The source
# is pinned in flake.lock and injected as `noctaliaSrc`.
#
# WE ALSO DO NOT USE THEIR HOME MODULE, for a sharper reason. It sets
# `xdg.configFile."noctalia/config.toml".source`, which makes the config a
# READ-ONLY STORE SYMLINK -- and Noctalia's whole configuration model is a
# settings GUI with hot reload. A shell whose settings panel cannot save is
# worse than one with no settings panel. This module therefore SEEDS the
# config once and never touches it again: the app owns the file.
#
# That is the same rule this repo applies elsewhere (settings.json is seeded,
# not owned) and the one my-boxes learned from `~/.config/git/config` being a
# store symlink, which makes `git config --global` fail forever.

let
  cfg = config.wasisabi;

  noctalia = pkgs.callPackage "${noctaliaSrc}/nix/package.nix" { };

  # The seed. Deliberately MINIMAL: enough that a fresh machine looks right
  # (the font the rest of the desktop uses, a dark theme), and nothing else.
  # Every other setting is the GUI's business, and anything written here that
  # the user later changes would look like a setting that "resets itself" if
  # this file were ever re-applied.
  seed = pkgs.writeText "noctalia-config.toml" ''
    # Seeded ONCE by wasisabi on first login, then yours. Edit freely, in this
    # file or in Noctalia's settings GUI; nothing rewrites it.
    [shell]
    font = "JetBrainsMono Nerd Font"

    [theme]
    mode = "dark"
  '';
in
lib.mkIf (cfg.enable && cfg.shell == "noctalia") {
  home.packages = [ noctalia ];

  # Seed-if-absent. `-n` is the whole contract: present file wins, always.
  # Runs before home-manager's file linking so a first login has the config in
  # place when the service starts.
  home.activation.seedNoctaliaConfig = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.config/noctalia"
    run cp -n ${seed} "$HOME/.config/noctalia/config.toml" || true
    run chmod u+w "$HOME/.config/noctalia/config.toml" || true
  '';

  # A user service rather than a compositor spawn, matching every other piece
  # of the session: restarting niri does not orphan the shell, and the shell
  # can be restarted without touching niri.
  systemd.user.services.noctalia = {
    Unit = {
      Description = "Noctalia - Wayland desktop shell";
      Documentation = "https://docs.noctalia.dev/";
      PartOf = [ config.wayland.systemd.target ];
      After = [ config.wayland.systemd.target ];
    };
    Service = {
      ExecStart = lib.getExe noctalia;
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ config.wayland.systemd.target ];
  };
}
