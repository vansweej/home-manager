{ pkgs, lib, config, inputs, meta, ... }:

let
  # Read the upstream opencode.json from the pinned ai-coding Nix store path and
  # overlay the athenaeum-mcp registration onto it. All other settings (model,
  # compaction, permission) are inherited from upstream unchanged. The overlay
  # adds only top-level mcp / tools / agent keys, which the upstream config does
  # not define, so there is no clobbering.
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
  m1OpencodeConfig = builtins.toJSON (
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
  # M1 MacBook-specific configuration.
  imports = [ ../athenaeum.nix ../cerebrum.nix ../choragos.nix ../claude.nix ../claude-mcp.nix ../dev-tools.nix ];

  # Override the shared opencode.json (deployed by opencode.nix) with a static
  # file that merges the athenaeum MCP overlay onto the upstream config.
  # NOTE: if ~/.config/opencode/opencode.json already exists as a plain file,
  # remove it before running home-manager switch:
  #   rm ~/.config/opencode/opencode.json
  home.file.".config/opencode/opencode.json".source = lib.mkForce
    (pkgs.writeText "m1-opencode.json" m1OpencodeConfig);

  # M1 defaults the raw pipeline CLI and /pipeline tool to bedrock-sonnet
  # (choragos inherits the same bedrock-sonnet default from
  # modules/choragos.nix's programs.choragos.defaultProfile option).
  home.sessionVariables = {
    AI_CODING_MODEL_PROFILE = "bedrock-sonnet";
  };

  # Create the mutable athenaeum data dir before any file writes. It is used as
  # the corpus-watcher unit's WorkingDirectory and log location below (the
  # athenaeum-mcp-server binary and athenaeum-ingest CLI self-locate their own
  # LanceDB store beneath this same path in-binary, so this mkdir no longer
  # needs to pre-create the /data subdirectory — the binary creates it lazily
  # on first write). The path comes from the athenaeum.nix option so it stays
  # in sync with what the watcher unit references. The old store under
  # ~/Projects/athenaeum-mcp is NOT migrated — re-ingest after switching.
  home.activation.createAthenaeumDataDir =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${config.programs.athenaeum.dataDir}"
      run mkdir -p "${config.programs.athenaeum.watchDir}"
    '';

  # Long-running corpus watcher (macOS). launchd keeps watchexec resident; it
  # invokes the short-lived athenaeum-ingest CLI on each debounced change.
  # ProgramArguments wraps watchCommand in `sh -lc` because launchd needs a list
  # and watchCommand is one string; -l (login shell) yields a sane PATH.
  # WorkingDirectory = dataDir is this unit's own cwd (for logs, below) — the
  # ingest subprocess itself no longer depends on cwd, since it self-locates its
  # LanceDB store in-binary. RunAtLoad + KeepAlive keep it running and relaunch
  # on exit. launchd has no journal, so stdout/stderr go to log files under
  # dataDir — kept out of watchDir so log writes cannot trigger the watcher.
  launchd.agents.athenaeum-watch = {
    enable = true;
    config = {
      ProgramArguments = [ "/bin/sh" "-lc" config.programs.athenaeum.watchCommand ];
      WorkingDirectory = config.programs.athenaeum.dataDir;
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${config.programs.athenaeum.dataDir}/watch.log";
      StandardErrorPath = "${config.programs.athenaeum.dataDir}/watch.err.log";
    };
  };
}
