{ lib, config, pkgs, ... }:

let cfg = config.wasisabi; in
{
  imports = [ ./options.nix ./core.nix ./boot.nix ./desktop.nix ./network.nix ];

  config = lib.mkIf cfg.enable {
    # ─── The libre rule, enforced at build time ───
    assertions = lib.optional cfg.enforceLibre {
      assertion = !(config.nixpkgs.config.allowUnfree or false);
      message = ''
        wasisabi: nixpkgs.config.allowUnfree = true, which violates the
        libre-only rule of this setup. Either keep allowUnfree = false, or
        explicitly opt out by setting wasisabi.enforceLibre = false.
      '';
    };
  };
}