{ pkgs, lib, config, ... }:
{
  # Parallels Ubuntu VM guest-image baseline. gh is enabled directly here
  # (not via dev-tools.nix, which also installs apm -- apm's prebuilt
  # binary throws on aarch64-linux, so dev-tools.nix is never imported on
  # this profile).
  programs.gh.enable = true;

  # Defaults the raw pipeline CLI / /pipeline tool to the free OpenCode Zen
  # profile, mirroring oryp6's AI_CODING_MODEL_PROFILE default.
  home.sessionVariables.AI_CODING_MODEL_PROFILE = "opencode-free";
}
