{ lib, config, ... }:

{
  imports = [ ./options.nix ./shell.nix ./terminal.nix ./desktop.nix ./apps.nix ];

  # Home state — the one thing that must exist somewhere on disk.
  home.stateVersion = lib.mkDefault "26.05";
}