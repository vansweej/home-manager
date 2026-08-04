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
  modelOverlay = {
    agent = {
      brainstorm = { model = "github-copilot/claude-opus-4.8"; };
      spar       = { model = "github-copilot/claude-opus-4.8"; };
      teach      = { model = "github-copilot/claude-opus-4.8"; };
      plan       = { model = "github-copilot/claude-opus-4.8"; };
      explore    = { model = "github-copilot/claude-opus-4.8"; };
    };
  };
  oryp6OpencodeConfig = builtins.toJSON (
    lib.recursiveUpdate
      (lib.recursiveUpdate
        (lib.recursiveUpdate
          (lib.recursiveUpdate baseConfig config.programs.athenaeum.opencodeOverlay)
          config.programs.cerebrum.opencodeOverlay)
        config.programs.choragos.opencodeOverlay)
      modelOverlay
  );
in
{
  imports = [ ../athenaeum.nix ../cerebrum.nix ../choragos.nix ../dev-tools.nix ];

  # oryp6 defaults to the free OpenCode Zen profile for both choragos and the
  # raw pipeline CLI / /pipeline tool (see AI_CODING_MODEL_PROFILE below).
  # Overrides the shared bedrock-sonnet default from modules/choragos.nix.
  programs.choragos.defaultProfile = "opencode-free";

  # Override the shared opencode.json (deployed by opencode.nix) with a static
  # file that merges the athenaeum MCP overlay onto the upstream config.
  # NOTE: if ~/.config/opencode/opencode.json already exists as a plain file,
  # remove it before running home-manager switch:
  #   rm ~/.config/opencode/opencode.json
  home.file.".config/opencode/opencode.json".source = lib.mkForce
    (pkgs.writeText "oryp6-opencode.json" oryp6OpencodeConfig);

  # Create the mutable athenaeum data dir before any file writes. It is used as
  # the corpus-watcher unit's WorkingDirectory below (the athenaeum-mcp-server
  # binary and athenaeum-ingest CLI self-locate their own LanceDB store beneath
  # this same path in-binary, so this mkdir no longer needs to pre-create the
  # /data subdirectory — the binary creates it lazily on first write). The path
  # comes from the athenaeum.nix option so it stays in sync with what the
  # watcher unit references. The old store under ~/Projects/athenaeum-mcp is
  # NOT migrated — re-ingest after switching.
  home.activation.createAthenaeumDataDir =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${config.programs.athenaeum.dataDir}"
      run mkdir -p "${config.programs.athenaeum.watchDir}"
    '';

  # oryp6-specific packages: rootless Docker runtime and its dependencies.
  home.packages = with pkgs; [
    docker

    slirp4netns   # required by rootless Docker for networking
    rootlesskit   # required by rootless Docker
  ];

  # Point the Docker CLI at the rootless user socket. AI_CODING_MODEL_PROFILE
  # defaults the raw pipeline CLI and the /pipeline OpenCode tool to
  # opencode-free (choragos is defaulted separately via
  # programs.choragos.defaultProfile above).
  home.sessionVariables = {
    DOCKER_HOST = "unix:///run/user/1000/docker.sock";
    AI_CODING_MODEL_PROFILE = "opencode-free";
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
  # is dataDir (NOT watchDir) purely as this unit's own cwd/log location — the
  # ingest subprocess itself no longer depends on cwd, since it self-locates its
  # LanceDB store in-binary. Pointing cwd at watchDir would be harmless for the
  # store now, but dataDir is kept for consistency with the log-file convention.
  # ExecStart is a plain argv string — systemd splits it on whitespace and
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
