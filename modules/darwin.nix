{ pkgs, lib, config, ... }:
{
  # macOS-specific configuration.
  # Add Darwin-only packages, settings, or launchd services here.

  # Ghostty is not packaged for Darwin in nixpkgs; install it via the .dmg from
  # https://ghostty.org or via Homebrew. Setting package = null skips installation
  # but still lets home-manager manage ~/.config/ghostty/config.
  programs.ghostty.package = null;
}
