{ lib, pkgs, config, ... }:

# Shell: zsh + starship + fzf + a modern CLI toolkit. Plain zsh (no oh-my-zsh
# framework) — fewer moving parts, everything here is OSS.

let cfg = config.wasisabi; in
lib.mkIf cfg.enable {
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history = {
      size = 50000;
      ignoreDups = true;
      share = true;
    };
    shellAliases = {
      ls = "eza --icons --group-directories-first";
      ll = "eza -la --icons --git";
      cat = "bat --style=plain";
      g = "git";
      nrs = "sudo nixos-rebuild switch --flake";
    };
  };

  programs.starship = {
    enable = true;
    # Defaults are tasteful; keep the prompt fast.
    settings = {
      add_newline = false;
      character = {
        success_symbol = "[❯](bold mauve)";
        error_symbol = "[❯](bold red)";
      };
    };
  };

  programs.fzf.enable = true;

  # Per-project dev environments, nix-native.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.packages = with pkgs; [
    eza
    bat
    unzip
    fastfetch
  ];
}