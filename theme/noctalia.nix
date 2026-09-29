# A palette from palettes.nix, in Noctalia's 16 colour roles. One mapping for
# the shell (home/noctalia.nix, as a palette file) and the greeter
# (modules/desktop.nix, as its sync.toml), so the login screen and the desktop
# behind it cannot drift apart.
#
# primary is `focus`: for sumi that is paper, so Noctalia's active elements are
# paper chips with ink text, like a print; for Catppuccin it is mauve.
p:
let h = x: "#${x}"; in
{
  primary = h p.focus;
  on_primary = h p.base;
  secondary = h p.highlight;
  on_secondary = h p.base;
  tertiary = h p.info;
  on_tertiary = h p.base;
  error = h p.urgent;
  on_error = h p.base;
  surface = h p.base;
  on_surface = h p.text;
  surface_variant = h p.surface0;
  on_surface_variant = h p.subtext;
  outline = h p.surface2;
  shadow = h p.crust;
  hover = h p.surface1;
  on_hover = h p.bright;
}
