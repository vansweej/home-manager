{ pkgs, lib, config, ... }:
{
  # macOS-specific configuration.
  # Add Darwin-only packages, settings, or launchd services here.

  # ghostty-bin fetches the official macOS DMG (aarch64-darwin + x86_64-darwin).
  # Linux machines use pkgs.ghostty (built from source) via the common.nix default.
  programs.ghostty.package = pkgs.ghostty-bin;
}
