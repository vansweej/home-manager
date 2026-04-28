{ pkgs, lib, config, ... }:
{
  # macOS-specific configuration.
  # Add Darwin-only packages, settings, or launchd services here.

  # ghostty-bin fetches the official macOS DMG (aarch64-darwin + x86_64-darwin).
  # Linux machines use pkgs.ghostty (built from source) via the common.nix default.
  programs.ghostty.package = pkgs.ghostty-bin;

  # macOS defaults to zsh; enable it so home.sessionPath and home.sessionVariables
  # (written to hm-session-vars.sh) are sourced on login.
  programs.zsh = {
    enable = true;
    initExtra = ''
      unset __HM_SESS_VARS_SOURCED
      . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
    '';
  };

  # Starship prompt in zsh (bash integration is enabled in common.nix).
  programs.starship.enableZshIntegration = true;
}
