{
  lib,
  pkgs,
  wasisabiSources,
  ...
}:

# The BUILDING BLOCKS of the agent layer: each one a service module with its
# own `enable`, entirely inert until something turns it on. modules/agents.nix
# is what turns them on for a wasisabi machine (with mkDefault, as everywhere
# else), from the few distro-level options in modules/options.nix.
#
# They live under `wasisabi.services.*` rather than `services.*` so that they
# can never collide with nixpkgs or with a consumer's own modules of the same
# purpose (the my-boxes fleet, where most of these were first built, declares
# its own `services.wherever`, `services.searxng`, ...).
#
# Several were carried over from that fleet, where they run on a real machine;
# see each file's header. Their comments reference that repository's notes
# (`work/notes/...`, `hosts/...`, ADR numbers): github.com/wighawag/my-boxes.
{
  imports = [
    ./llm.nix
    ./searxng.nix
    ./pi-user.nix
    ./wherever.nix
    ./anon-accounts.nix
    ./anonctl-units.nix
    ./anon-dns.nix
    ./anon-home.nix
    ./anon-search.nix
    ./wherever-anon.nix
    ./wherever-anon-reconcile.nix
    ./anon-dispatcher.nix
    ./interactive-shell.nix
  ];

  options.wasisabi.pkgs = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.package;
    description = ''
      The packages the agent layer runs, built against THIS system's pkgs.
      Each is a mkDefault, so a single one can be substituted, e.g.
      `wasisabi.pkgs.wherever = myWherever;`, and the rest are kept.
    '';
  };

  # Per attribute, not as an option default: a default is replaced wholesale by
  # any definition, so overriding one package would have dropped all the others.
  config.wasisabi.pkgs = lib.mapAttrs (_: lib.mkDefault) (
    import ../../pkgs {
      inherit pkgs;
      sources = wasisabiSources;
    }
  );
}
