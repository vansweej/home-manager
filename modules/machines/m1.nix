{ pkgs, lib, config, inputs, meta, ... }:

let
  # Read the upstream opencode.json from the pinned ai-coding Nix store path and
  # overlay the athenaeum-mcp registration onto it. All other settings (model,
  # compaction, permission) are inherited from upstream unchanged. The overlay
  # adds only top-level mcp / tools / agent keys, which the upstream config does
  # not define, so there is no clobbering.
  aiCodingPkg = inputs.ai-coding.packages.${meta.system}.default;
  baseConfig = builtins.fromJSON (builtins.readFile "${aiCodingPkg}/opencode.json");
  m1OpencodeConfig = builtins.toJSON (
    lib.recursiveUpdate baseConfig config.programs.athenaeum.opencodeOverlay
  );
in
{
  # M1 MacBook-specific configuration.
  imports = [ ../athenaeum.nix ];

  # Override the shared opencode.json (deployed by opencode.nix) with a static
  # file that merges the athenaeum MCP overlay onto the upstream config.
  # NOTE: if ~/.config/opencode/opencode.json already exists as a plain file,
  # remove it before running home-manager switch:
  #   rm ~/.config/opencode/opencode.json
  home.file.".config/opencode/opencode.json".source = lib.mkForce
    (pkgs.writeText "m1-opencode.json" m1OpencodeConfig);
}
