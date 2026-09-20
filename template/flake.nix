{
  description = "My machine on wasi-sabi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wasisabi = {
      url = "github:wighawag/wasisabi";
      # Point wasisabi at YOUR pins rather than its own. The module layers are
      # plain modules -- `pkgs` comes from the nixosSystem that imports them --
      # so this is what makes them evaluate against the nixpkgs above.
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      inputs.nixos-hardware.follows = "nixos-hardware";
    };
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, wasisabi, nixos-hardware, ... }: {
    nixosConfigurations.CHANGEME_HOSTNAME = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit wasisabi; };
      modules = [
        # ── The wasisabi system layer: services, programs, sane defaults ──
        # Everything it sets is mkDefault, so anything you write in
        # configuration.nix wins. Inert until `wasisabi.enable = true` there.
        wasisabi.nixosModules.wasisabi

        ./configuration.nix
        home-manager.nixosModules.home-manager

        # ── Your hardware layer ──
        # Pick your module from https://github.com/NixOS/nixos-hardware:
        # e.g. ThinkPad T14s Gen 3 AMD:
        #   nixos-hardware.nixosModules.lenovo-thinkpad-t14s-amd
      ];
    };
  };
}