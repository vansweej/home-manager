{ pkgs, lib, config, inputs, meta, ... }:
let
  # Read the upstream opencode.json from the pinned ai-coding Nix store path and
  # overlay both the M5-specific provider block and the athenaeum-mcp server
  # registration onto it. All other settings — model, compaction, permission —
  # are inherited from the upstream file so they can never drift out of sync with
  # the other machines.
  #
  # Merge order: upstream base ← Ollama provider ← athenaeum overlay. The two
  # overlays touch disjoint top-level keys (provider.* vs mcp.* / tools.* /
  # agent.*), so there is no collision. This stays a single merge feeding the
  # single lib.mkForce write below — adding a second opencode.json definition
  # would conflict with that mkForce.
  #
  # lib.recursiveUpdate merges attrsets deeply but replaces lists wholesale. The
  # current schema has no lists at overlapping keys under provider / mcp / tools
  # / agent, so there is no collision risk. If that changes, revisit.
  aiCodingPkg = inputs.ai-coding.packages.${meta.system}.default;
  baseConfig = builtins.fromJSON (builtins.readFile "${aiCodingPkg}/opencode.json");
  m5OpencodeConfig = builtins.toJSON (lib.recursiveUpdate
    (lib.recursiveUpdate baseConfig {
      provider = {
        ollama = {
          npm = "@ai-sdk/openai-compatible";
          name = "Ollama (local)";
          options = {
            baseURL = "http://localhost:11434/v1";
          };
          models = {
            "gemma4:26b" = {
              name = "Gemma 4 26B (local)";
              limit = {
                context = 32768;
                output = 8192;
              };
            };
          };
        };
      };
    })
    config.programs.athenaeum.opencodeOverlay);

  # M5-specific local agent.
  # Mirrors opencode/agents/local.md exactly, with model and description
  # overridden for Ollama. The markdown frontmatter model field is authoritative
  # for markdown-defined agents — opencode.json agent.local.model cannot
  # override it. lib.strings.trim strips the leading indentation from the
  # Nix indented string so the deployed file has no spurious whitespace.
  # If the shared prompt body changes, keep this in sync.
  m5LocalAgent = lib.strings.trim ''
    ---
    description: General-purpose development with Gemma 4 26B (local Ollama)
    mode: primary
    model: ollama/gemma4:26b
    temperature: 0.3
    steps: 10
    permission:
      pipeline: allow
    ---

    You are a coding assistant. Use tools to complete tasks.

    At the start of every task, call the `skill-retrieval` tool with `action: "edit"`
    and a brief `query` describing what you are about to do. Use the returned skill
    content as additional context.

    **Scaffolding a new project:** call the pipeline tool with the pipeline name and workspace path.
    Available pipelines: scaffold-rust, scaffold-cpp, dev-cycle, rust-dev-cycle, cmake-dev-cycle.

    **Adding Rust dependencies:** use `cargo add <crate>` via bash (use `nix develop . --command cargo add <crate>` if there is a flake.nix).
  '';
in
{
  imports = [
    ../claude-code.nix
    ../athenaeum.nix
  ];

  # M5 MacBook-specific configuration.

  home.packages = with pkgs; [
    awscli2
  ];

  # Override the shared opencode.json symlink (deployed by opencode.nix) with a
  # static file that merges the Ollama provider onto the upstream config. All
  # other settings (model, compaction, permission) are inherited from ai-coding.
  # NOTE: if ~/.config/opencode/opencode.json already exists as a plain file
  # (e.g. written by OpenCode before the first home-manager switch), remove it
  # before running home-manager switch:
  #   rm ~/.config/opencode/opencode.json
  home.file.".config/opencode/opencode.json".source = lib.mkForce
    (pkgs.writeText "m5-opencode.json" m5OpencodeConfig);

  # Override the shared local.md agent (deployed by opencode.nix auto-discovery)
  # with an M5-specific version whose frontmatter sets model: ollama/gemma4:26b.
  # The frontmatter model field is authoritative for markdown-defined agents and
  # cannot be overridden from opencode.json alone.
  home.file.".config/opencode/agents/local.md".source = lib.mkForce
    (pkgs.writeText "m5-local-agent.md" m5LocalAgent);

  # Create the mutable athenaeum data dir (cwd for the MCP server) before any
  # file writes. The path comes from the athenaeum.nix option so it stays in sync
  # with the server's cwd. The old store under ~/Projects/athenaeum-mcp is NOT
  # migrated — re-ingest after switching.
  home.activation.createAthenaeumDataDir =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${config.programs.athenaeum.dataDir}/data"
      run mkdir -p "${config.programs.athenaeum.watchDir}"
    '';

  # Long-running corpus watcher (macOS). launchd keeps watchexec resident; it
  # invokes the short-lived athenaeum-ingest CLI on each debounced change.
  # ProgramArguments wraps watchCommand in `sh -lc` because launchd needs a list
  # and watchCommand is one string; -l (login shell) yields a sane PATH.
  # WorkingDirectory = dataDir is a second cwd guarantee on top of watchexec
  # --workdir, ensuring the CLI's relative db_path (./data/athenaeum) resolves to
  # the shared store rather than a stray DB in the corpus. RunAtLoad + KeepAlive
  # keep it running and relaunch on exit. launchd has no journal, so stdout/stderr
  # go to log files under dataDir — kept out of watchDir so log writes cannot
  # trigger the watcher.
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
