{
  description = "wasi-sabi — an opinionated, libre-only Wayland desktop, distributed as NixOS + home-manager modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The Noctalia shell, as SOURCE not as a flake: its own flake pins a
    # separate nixos-unstable, which would put a second nixpkgs in every
    # consumer's closure and let the shell's GL stack drift from the
    # compositor's. nix/package.nix is a plain callPackage file, so we build
    # it against our pkgs. See home/noctalia.nix.
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      flake = false;
    };

    # Used by the INSTALLER only (partitioning, and the hardware module the
    # generated flake offers users). Flake inputs are fetched on access, so
    # consumers who only import the module layers never pull these.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      # Follow our nixpkgs rather than letting it drag in a second one. This
      # also keeps the lock graph flat, which is what lets installer/lock.nix
      # hand the installed machine a lock that nix accepts as-is instead of
      # re-resolving on first boot.
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      noctalia,
      disko,
      nixos-hardware,
      ...
    }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};

      # The release this tree installs. New machines get it as their
      # stateVersion: it records what a machine was FIRST installed from, so
      # it is a property of the installer media and never an answer.
      release = lib.trivial.release;

      # ── the installer, generated from the options ──
      questions = import ./installer/questions.nix { inherit lib; };
      questionsJson = pkgs.writeText "wasisabi-questions.json" (builtins.toJSON questions);
      targetLock = pkgs.callPackage ./installer/lock.nix { inherit self; };

      mkInstaller =
        { offline }:
        pkgs.callPackage ./installer/package.nix {
          inherit offline targetLock;
          questions = questionsJson;
          template = ./template;
          stateVersion = release;
          nixpkgsSource = nixpkgs;
        };

      payloads = import ./installer/payloads.nix {
        inherit
          lib
          self
          system
          questions
          ;
        nixosSystem = nixpkgs.lib.nixosSystem;
        homeManagerModule = home-manager.nixosModules.home-manager;
        stateVersion = release;
      };

      # The unattended answers for the VM test, derived from one file so the
      # plain and LUKS runs cannot drift apart.
      autotestAnswers =
        diskLayout:
        pkgs.runCommand "wasisabi-autotest-answers-${diskLayout}.json" { nativeBuildInputs = [ pkgs.jq ]; }
          ''
            jq '.["disk:layout"] = "${diskLayout}"
                | .["disk:passphrase"] = "testpassphrase"' \
              ${./installer/test-answers-vm.json} > $out
          '';

      mkIso =
        {
          offline,
          autotest ? null,
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit offline autotest;
            installer = mkInstaller { inherit offline; };
            nixpkgsSource = nixpkgs;
            # Everything the generated flake.lock names, so that the install
            # resolves entirely from the medium.
            sources = [
              self
              nixpkgs
              home-manager
              noctalia
              disko
              nixos-hardware
            ];
            wasisabiRev = self.rev or "dirty";
            payloads = lib.optionals offline payloads.toplevels;
          };
          modules = [ ./hosts/iso.nix ];
        };

      # ── the emit-roundtrip check ──
      # Run the real emitter on a canned answer file, then evaluate what it
      # produced as a real NixOS configuration and assert that the answers
      # actually took effect. This is the join between template/ and the
      # installer: if either drifts, this stops evaluating or stops matching.
      emitted =
        pkgs.runCommand "wasisabi-emitted-flake"
          {
            nativeBuildInputs = [
              pkgs.jq
              pkgs.python3
            ];
          }
          ''
            bash ${./installer/emit.sh} \
              --questions ${questionsJson} \
              --answers ${./installer/test-answers.json} \
              --template ${./template} \
              --out $out \
              --state-version ${release}
            cp ${./installer/test-hardware.nix} $out/hardware-configuration.nix
          '';

      emittedSystem = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          wasisabi = self;
        };
        modules = [
          self.nixosModules.wasisabi
          home-manager.nixosModules.home-manager
          "${emitted}/configuration.nix"
        ];
      };
    in
    {
      # System-level layer: services, programs, sane hardware-agnostic defaults.
      # Knows nothing about your disks, drivers or CPU.
      nixosModules.wasisabi = import ./modules;

      # User-level layer: apps, dotfiles, keybinds, theming.
      # Also usable standalone with home-manager on any distro.
      homeModules.wasisabi = {
        imports = [ ./home ];
        # Injected rather than fetched inside the module, so the pin lives in
        # flake.lock (updatable with `nix flake update noctalia`) and consumers
        # need to wire nothing.
        _module.args.noctaliaSrc = noctalia;
      };

      # A demo machine proving the layers are hardware-agnostic:
      #   nixos-rebuild build-vm --flake .#demo   → boots the whole desktop in QEMU
      nixosConfigurations.demo = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self; };
        modules = [
          home-manager.nixosModules.home-manager
          self.nixosModules.wasisabi
          (
            { config, ... }:
            {
              # Wire the home layer for the demo user.
              home-manager.users.demo = {
                imports = [ self.homeModules.wasisabi ];
                wasisabi.enable = true;
                # QEMU on a desktop host: your compositor eats Super+key before the
                # VM can see it. Use ALT in the VM; back to SUPER on real hardware.
                wasisabi.modKey = "ALT";
                # The demo VM renders through VirGL, which is a real GL stack but
                # not a fast one. Animations are full-screen redraws; turn them off.
                wasisabi.animations = false;
                # Ghostty compiles its shaders on first launch, which on a virtual
                # GPU takes ~35s before a window appears. foot is CPU-rendered and
                # opens instantly, which is what you want when kicking the tyres.
                # On real hardware the default (ghostty) is fine.
                wasisabi.terminal = "foot";
              };
            }
          )
          ./hosts/demo.nix
        ];
      };

      # The installer media. Both install the exact revision they were built
      # from; see installer/lock.nix for why that matters.
      nixosConfigurations.isoNetinstall = mkIso { offline = false; };
      nixosConfigurations.isoOffline = mkIso { offline = true; };

      # Test media: identical to the above but installs unattended and powers
      # off. Built by scripts/test-install-vm.sh, not meant for a USB stick.
      nixosConfigurations.isoAutotest = mkIso {
        offline = false;
        autotest = autotestAnswers "plain";
      };
      nixosConfigurations.isoAutotestLuks = mkIso {
        offline = false;
        autotest = autotestAnswers "luks";
      };
      nixosConfigurations.isoAutotestOffline = mkIso {
        offline = true;
        autotest = autotestAnswers "plain";
      };

      packages.${system} = {
        default = self.packages.${system}.installer;
        installer = mkInstaller { offline = false; };
        questions = questionsJson;
        target-lock = targetLock;
        iso-netinstall = self.nixosConfigurations.isoNetinstall.config.system.build.isoImage;
        iso-offline = self.nixosConfigurations.isoOffline.config.system.build.isoImage;
        iso-autotest = self.nixosConfigurations.isoAutotest.config.system.build.isoImage;
        iso-autotest-luks = self.nixosConfigurations.isoAutotestLuks.config.system.build.isoImage;
        iso-autotest-offline = self.nixosConfigurations.isoAutotestOffline.config.system.build.isoImage;
      };

      checks.${system} =
        let
          c = emittedSystem.config;
          home = c.home-manager.users.wighawag.wasisabi;

          # Answers from installer/test-answers.json, and what each one should
          # have done to the evaluated system.
          expectations = [
            {
              name = "hostname is substituted";
              expected = "kestrel";
              actual = c.networking.hostName;
            }
            {
              name = "the user account exists";
              expected = true;
              actual = c.users.users ? wighawag;
            }
            {
              name = "no password material reached the config";
              expected = null;
              actual = c.users.users.wighawag.initialPassword;
            }
            {
              name = "stateVersion is the installing release";
              expected = release;
              actual = c.system.stateVersion;
            }
            {
              name = "the keyboard answer reaches xkb";
              expected = "fr";
              actual = c.services.xserver.xkb.layout;
            }
            {
              name = "the keyboard answer reaches localed's file";
              expected = true;
              actual = lib.hasInfix ''"XkbLayout" "fr"'' c.environment.etc."X11/xorg.conf.d/00-keyboard.conf".text;
            }
            {
              name = "the console follows the same layout";
              expected = true;
              actual = c.console.useXkbConfig;
            }
            {
              name = "xkb options reach xkb";
              expected = "caps:escape";
              actual = c.services.xserver.xkb.options;
            }
            {
              name = "a false answer is honoured (tor)";
              expected = false;
              actual = c.services.tor.enable;
            }
            {
              name = "the greeter answer is honoured";
              expected = true;
              actual = c.services.greetd.settings.default_session.command != null;
            }
            {
              name = "splash off means no plymouth";
              expected = false;
              actual = c.boot.plymouth.enable;
            }
            {
              name = "the firmware answer is honoured";
              expected = true;
              actual = c.hardware.enableRedistributableFirmware;
            }
            {
              name = "the detected GPU driver reaches the initrd";
              expected = true;
              actual = lib.elem "amdgpu" c.boot.initrd.kernelModules;
            }
            {
              name = "home answers reach the home layer (browser)";
              expected = "librewolf";
              actual = home.browser;
            }
            {
              name = "home answers reach the home layer (shell)";
              expected = "classic";
              actual = home.shell;
            }
            {
              name = "an optional app answer is honoured";
              expected = true;
              actual = home.apps.office;
            }
            # test-answers.json deliberately leaves these two out, one per
            # layer: an option nobody answered must keep tracking wasisabi's
            # default rather than being frozen into the generated config.
            {
              name = "an unanswered home option keeps the project default";
              expected = "neovim";
              actual = home.editor;
            }
            {
              name = "an unanswered system option keeps the project default";
              expected = "";
              actual = c.services.xserver.xkb.variant;
            }
            {
              name = "unanswered options are not written into the config";
              expected = false;
              actual = lib.hasInfix "wasisabi.editor" (builtins.readFile "${emitted}/configuration.nix");
            }
          ];

          failures = lib.filter (e: e.actual != e.expected) expectations;

          report = lib.concatMapStringsSep "\n  " (
            e: "${e.name}: expected ${builtins.toJSON e.expected}, got ${builtins.toJSON e.actual}"
          ) failures;
        in
        {
          # `niri validate` runs inside this derivation, which is the reason
          # the compositor was chosen. Until it was a check, nothing in
          # `nix flake check` ever built it, so nothing ever ran it.
          niri-config = self.nixosConfigurations.demo.config.home-manager.users.demo.xdg.configFile."niri/config.kdl".source;

          # Forces the coverage rule in installer/questions.nix.
          installer-questions = questionsJson;

          installer-lint =
            pkgs.runCommand "wasisabi-installer-lint" { nativeBuildInputs = [ pkgs.shellcheck ]; }
              ''
                shellcheck --shell=bash --severity=style \
                  ${./installer/install.sh} ${./installer/emit.sh}
                touch $out
              '';

          emit-roundtrip = lib.throwIf (failures != [ ]) ''
            wasisabi: the installer emitted a config that does not do what was answered:
              ${report}
          '' pkgs.runCommand "wasisabi-emit-roundtrip" { } ''
            # Referencing the toplevel's drvPath forces the whole generated
            # configuration to EVALUATE (so a broken option fails here) while
            # deliberately not building the desktop, which is what the VM
            # install test is for.
            echo ${builtins.hashString "sha256" emittedSystem.config.system.build.toplevel.drvPath} > $out
            cp ${emitted}/configuration.nix $out-config 2>/dev/null || true
          '';

          # The offline ISO's claim, checked: every value of every enum
          # appears in some payload.
          payload-coverage = pkgs.writeText "wasisabi-payload-coverage.json" (
            builtins.toJSON {
              inherit (payloads) count coverage;
            }
          );
        }
        # The lock can only be pinned from a committed tree, so this check
        # exists when there is a revision to pin and not during local edits.
        // { target-lock = targetLock; };

      # The "installer experience" for people who would rather not use an ISO:
      # scaffolds the same flake the installer writes.
      #   nix flake new -t github:wighawag/wasisabi ~/systems/my-laptop
      templates.default = {
        path = ./template;
        description = "A new machine on wasi-sabi: fill in your username, drop in hardware-configuration.nix, rebuild.";
      };
    };
}
