{
  # Distributable guest-VM image: this profile is deployed to colleagues'
  # Parallels Ubuntu VMs to give them the full OpenCode agent/skill/command/
  # tool surface plus the ai-os MCP stack (cerebrum, athenaeum, choragos,
  # argus, pavo) without manually assembling a home-manager configuration.
  #
  # `username = "parallels"` / `homeDirectory = "/home/parallels"` is a
  # DELIBERATE distribution convention, not an accident: the guest VM's
  # Ubuntu user account must be created with exactly this name so that
  # `home-manager switch --flake .#parallels-ubuntu` targets the right home
  # directory. Do not "fix" this to match any individual developer's own
  # username.
  system = "aarch64-linux";
  username = "parallels";
  homeDirectory = "/home/parallels";
  stateVersion = "25.11";
  cudaSupport = false;
}
