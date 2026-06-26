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
    lib.recursiveUpdate
      (lib.recursiveUpdate baseConfig config.programs.athenaeum.opencodeOverlay)
      config.programs.cerebrum.opencodeOverlay
  );
in
{
  imports = [ ../athenaeum.nix ../cerebrum.nix ];

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
      run mkdir -p "${config.programs.athenaeum.watchDir}"
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

  # Long-running corpus watcher. watchexec is the only resident process; it invokes
  # the short-lived athenaeum-ingest CLI on each debounced change. WorkingDirectory
  # is dataDir (NOT watchDir) as a second cwd guarantee on top of watchexec
  # --workdir, so the CLI's relative db_path (./data/athenaeum) resolves to the
  # shared store. Pointing cwd at watchDir would create a stray DB inside the
  # corpus. ExecStart is a plain argv string — systemd splits it on whitespace and
  # runs it without a shell. Restart = "always" mirrors macOS launchd KeepAlive;
  # systemd's default start-limit (5/10s) guards a crash-loop. Output goes to the
  # systemd journal (journalctl --user -u athenaeum-watch).
  systemd.user.services.athenaeum-watch = {
    Unit = {
      Description = "Athenaeum corpus watcher (reingest on PDF/EPUB change)";
      After = [ "default.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = config.programs.athenaeum.watchCommand;
      WorkingDirectory = config.programs.athenaeum.dataDir;
      Restart = "always";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
