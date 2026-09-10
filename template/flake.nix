{
  description = "My machine on wasi-sabi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wasisabi = {
      url = "github:YOUR_GITHUB_NAME/wasisabi";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware";
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