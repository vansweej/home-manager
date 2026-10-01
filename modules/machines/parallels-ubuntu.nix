{ pkgs, lib, config, inputs, meta, ... }:

let
  # Read the upstream opencode.json from the pinned ai-coding Nix store path and
  # overlay the athenaeum-mcp / cerebrum-mcp / choragos registrations onto it.
  # All other settings (model, compaction, permission) are inherited from
  # upstream unchanged. The overlay adds only top-level mcp / tools / agent
  # keys, which the upstream config does not define, so there is no clobbering.
  # lib.recursiveUpdate replaces lists wholesale, but neither side introduces
  # overlapping top-level lists.
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
  parallelsUbuntuOpencodeConfig = builtins.toJSON (
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
  imports = [
    ../choragos.nix
    ../cerebrum.nix
    ../athenaeum.nix
    ../argus.nix
    ../pavo.nix
  ];

  # Parallels Ubuntu VM guest-image baseline. gh is enabled directly here
  # (not via dev-tools.nix, which also installs apm -- apm's prebuilt
  # binary throws on aarch64-linux, so dev-tools.nix is never imported on
  # this profile).
  programs.gh.enable = true;

  # Defaults the raw pipeline CLI / /pipeline tool to the free OpenCode Zen
  # profile, mirroring oryp6's AI_CODING_MODEL_PROFILE default.
  home.sessionVariables.AI_CODING_MODEL_PROFILE = "opencode-free";

  # Mirrors oryp6: defaults choragos to the free OpenCode Zen profile too.
  programs.choragos.defaultProfile = "opencode-free";

  # Override the shared opencode.json (deployed by opencode.nix) with a static
  # file that merges the athenaeum / cerebrum / choragos MCP overlays onto the
  # upstream config.
  # NOTE: if ~/.config/opencode/opencode.json already exists as a plain file,
  # remove it before running home-manager switch:
  #   rm ~/.config/opencode/opencode.json
  home.file.".config/opencode/opencode.json".source = lib.mkForce
    (pkgs.writeText "parallels-ubuntu-opencode.json" parallelsUbuntuOpencodeConfig);

  # Create the mutable athenaeum data dir before any file writes. It is used as
  # the corpus-watcher unit's WorkingDirectory below (the athenaeum-mcp-server
  # binary and athenaeum-ingest CLI self-locate their own LanceDB store beneath
  # this same path in-binary, so this mkdir no longer needs to pre-create the
  # /data subdirectory -- the binary creates it lazily on first write). The
  # path comes from the athenaeum.nix option so it stays in sync with what the
  # watcher unit references.
  home.activation.createAthenaeumDataDir =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${config.programs.athenaeum.dataDir}"
      run mkdir -p "${config.programs.athenaeum.watchDir}"
    '';

  # Long-running corpus watcher (Linux/systemd form -- this is a per-machine
  # Linux module, so the macOS launchd form must NOT be used here).
  # watchexec is the only resident process; it invokes the short-lived
  # athenaeum-ingest CLI on each debounced change. WorkingDirectory is dataDir
  # (NOT watchDir) purely as this unit's own cwd/log location -- the ingest
  # subprocess itself no longer depends on cwd, since it self-locates its
  # LanceDB store in-binary. ExecStart is a plain argv string -- systemd
  # splits it on whitespace and runs it without a shell. Output goes to the
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
