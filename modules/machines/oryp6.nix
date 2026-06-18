{ pkgs, lib, config, inputs, meta, ... }:

let
  # Read the upstream opencode.json from the pinned ai-coding Nix store path and
  # overlay the athenaeum-mcp registration onto it. All other settings (model,
  # compaction, permission) are inherited from upstream unchanged. The overlay
  # adds only top-level mcp / tools / agent keys, which the upstream config does
  # not define, so there is no clobbering. lib.recursiveUpdate replaces lists
  # wholesale, but neither side introduces overlapping top-level lists.
  aiCodingPkg = inputs.ai-coding.packages.${meta.system}.default;
  baseConfig = builtins.fromJSON (builtins.readFile "${aiCodingPkg}/opencode.json");
  oryp6OpencodeConfig = builtins.toJSON (
    lib.recursiveUpdate baseConfig config.programs.athenaeum.opencodeOverlay
  );
in
{
  imports = [ ../athenaeum.nix ];

  # Override the shared opencode.json (deployed by opencode.nix) with a static
  # file that merges the athenaeum MCP overlay onto the upstream config.
  # NOTE: if ~/.config/opencode/opencode.json already exists as a plain file,
  # remove it before running home-manager switch:
  #   rm ~/.config/opencode/opencode.json
  home.file.".config/opencode/opencode.json".source = lib.mkForce
    (pkgs.writeText "oryp6-opencode.json" oryp6OpencodeConfig);

  # Create the mutable athenaeum data dir (cwd for the MCP server) before any
  # file writes. The path comes from the athenaeum.nix option so it stays in sync
  # with the server's cwd. The old store under ~/Projects/athenaeum-mcp is NOT
  # migrated — re-ingest after switching.
  home.activation.createAthenaeumDataDir =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${config.programs.athenaeum.dataDir}/data"
    '';

  # oryp6-specific packages: rootless Docker runtime and its dependencies.
  home.packages = with pkgs; [
    docker

    slirp4netns   # required by rootless Docker for networking
    rootlesskit   # required by rootless Docker
  ];

  # Point the Docker CLI at the rootless user socket.
  home.sessionVariables = {
    DOCKER_HOST = "unix:///run/user/1000/docker.sock";
  };

  # Register a user-level systemd service for the rootless Docker daemon.
  systemd.user.services.docker = {
    Unit = {
      Description = "Docker Application Container Engine (Rootless)";
      After = [ "default.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.docker}/bin/dockerd-rootless";
      Environment = [
        "PATH=${pkgs.docker}/bin:${pkgs.slirp4netns}/bin:${pkgs.rootlesskit}/bin:/run/wrappers/bin:/usr/bin:/run/current-system/sw/bin"
      ];
      Restart = "on-failure";
      TimeoutStartSec = 0;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
