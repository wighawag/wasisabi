{
  description = "wasi-sabi — an opinionated, libre-only Wayland desktop, distributed as NixOS + home-manager modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }: {
    # System-level layer: services, programs, sane hardware-agnostic defaults.
    # Knows nothing about your disks, drivers or CPU.
    nixosModules.wasisabi = import ./modules;

    # User-level layer: apps, dotfiles, keybinds, theming.
    # Also usable standalone with home-manager on any distro.
    homeModules.wasisabi = import ./home;

    # A demo machine proving the layers are hardware-agnostic:
    #   nixos-rebuild build-vm --flake .#demo   → boots the whole desktop in QEMU
    nixosConfigurations.demo = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit self; };
      modules = [
        home-manager.nixosModules.home-manager
        self.nixosModules.wasisabi
        ({ config, ... }: {
          # Wire the home layer for the demo user.
          home-manager.users.demo = {
            imports = [ self.homeModules.wasisabi ];
            wasisabi.enable = true;
            # QEMU on a desktop host: your compositor eats Super+key before the
            # VM can see it. Use ALT in the VM; back to SUPER on real hardware.
            wasisabi.modKey = "ALT";
          };
        })
        ./hosts/demo.nix
      ];
    };

    # The "installer experience": scaffolds a new machine's flake + config.
    #   nix flake new -t github:YOURNAME/wasisabi ~/systems/my-laptop
    templates.default = {
      path = ./template;
      description = "A new machine on wasi-sabi: fill in your username, drop in hardware-configuration.nix, rebuild.";
    };
  };
}