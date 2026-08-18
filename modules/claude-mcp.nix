{ config, lib, pkgs, inputs, meta, ... }:

let
  athenaeumPkg = inputs.athenaeum.packages.${meta.system}.default;
  choragosPkg  = inputs.choragos.packages.${meta.system}.default;
  aiCodingPkg  = inputs.ai-coding.packages.${meta.system}.default;

  # Stable per-user wrapper commands, deployed via home.packages (so they land
  # at ~/.nix-profile/bin/<name> on PATH — the same pattern already used by the
  # `choragos` CLI wrapper in choragos.nix). Claude Code's ~/.claude.json is
  # write-once: `claude mcp add-json` registers a server ONE TIME, and nothing
  # ever rewrites that file on later `home-manager switch` runs (unlike
  # OpenCode's opencode.json, which IS rewritten every switch). If we pointed
  # Claude directly at a raw /nix/store/<hash> path, that entry would go stale
  # the moment a flake input bumps. Pointing it at a stable wrapper instead
  # means the *path* Claude calls never changes — only the wrapper's target
  # store path (`.nix-profile` is repointed at each new generation) — so the
  # registration survives every future flake update with no re-registration.
  #
  # Both athenaeum and cerebrum now self-locate their LanceDB data directory
  # in-binary (XDG_DATA_HOME, else HOME/.local/share — see athenaeum.nix's and
  # cerebrum.nix's default_data_dir comments), so neither wrapper needs a `cd`
  # or any environment variable: a bare `exec` of the real binary is correct on
  # any client, including Claude Code's stdio transport, which has no `cwd`
  # field at all (unlike OpenCode's mcp.<name>.cwd).
  cerebrumMcpWrapper = pkgs.writeShellScriptBin "cerebrum-mcp" ''
    exec env \
      CEREBRUM_TABLE_NAME="memories_qwen3" \
      CEREBRUM_EMBED_MODEL="qwen3-embedding:0.6b" \
      CEREBRUM_EMBEDDING_DIM="1024" \
      ${config.programs.cerebrum.binPath} "$@"
  '';

  athenaeumMcpWrapper = pkgs.writeShellScriptBin "athenaeum-mcp" ''
    exec ${athenaeumPkg}/bin/athenaeum-mcp-server "$@"
  '';

  # choragos-mcp-server DOES need environment variables baked in (it has no
  # in-binary self-location — it shells out to the ai-coding monorepo and to
  # the cerebrum binary, per choragos.nix's own opencodeOverlay registration).
  # Baking them into the wrapper — rather than into a Claude `env` block, which
  # would embed the same churning /nix/store/<hash> paths choragos.nix computes
  # for OpenCode — keeps the ~/.claude.json entry itself stable across bumps.
  choragosMcpWrapper = pkgs.writeShellScriptBin "choragos-mcp" ''
    exec env \
      AI_CODING_MONOREPO="${aiCodingPkg}" \
      CHORAGOS_DEFAULT_PROFILE="${config.programs.choragos.defaultProfile}" \
      CEREBRUM_BIN="${config.programs.cerebrum.binPath}" \
      "${choragosPkg}/bin/choragos-mcp-server" "$@"
  '';

  homeBinDir        = "${config.home.homeDirectory}/.nix-profile/bin";
  cerebrumMcpPath   = "${homeBinDir}/cerebrum-mcp";
  athenaeumMcpPath  = "${homeBinDir}/athenaeum-mcp";
  choragosMcpPath   = "${homeBinDir}/choragos-mcp";

  # JSON bodies for `claude mcp add-json <name> -s user '<json>'`. Registered
  # at USER scope (available in every project, not just the one where `claude`
  # first ran) — see docs.claude.com/en/docs/claude-code/mcp#user-scope.
  # Non-exclusive and outside ~/.claude/settings.json entirely: Claude Code
  # NEVER stores MCP server definitions in settings.json (only approval/allow-
  # deny keys live there), so this cannot clobber the corporate Bedrock config
  # that claude.nix deliberately leaves undeclared (see claude.nix's own
  # comment on that invariant).
  serverConfigs = {
    cerebrum-mcp  = builtins.toJSON { type = "stdio"; command = cerebrumMcpPath; };
    athenaeum-mcp = builtins.toJSON { type = "stdio"; command = athenaeumMcpPath; };
    choragos-mcp  = builtins.toJSON {
      type = "stdio";
      command = choragosMcpPath;
      # choragos_run_plan drives a full plan-cycle run, which can take several
      # minutes — mirrors the same timeout choragos.nix sets for OpenCode's MCP
      # client (the 5s MCP default would abort it mid-run otherwise).
      timeout = 600000;
    };
  };
in
{
  config.home.packages = [ cerebrumMcpWrapper athenaeumMcpWrapper choragosMcpWrapper ];

  # Idempotent registration, run once per server per machine. `claude mcp get
  # <name>` exits non-zero when the server isn't registered yet; re-running
  # `claude mcp add-json` for an already-registered name errors ("already
  # exists"), so the guard is required, not just a nicety.
  #
  # `claude` is installed by the separate ~/.aits-claude-code-setup tool at
  # $HOME/.local/bin/claude, NOT managed by this flake and NOT on the
  # activation script's own hermetic PATH (home-manager's activation script
  # sets an explicit PATH containing only Nix store tool paths — it does not
  # inherit the interactive shell's PATH, so a plain `command -v claude` here
  # always fails even when claude genuinely is installed). Resolve it
  # explicitly: prefer PATH if some other mechanism already put it there, else
  # fall back to the known install location. Skips entirely (no error) when
  # neither resolves — e.g. a machine where Claude Code hasn't been installed.
  config.home.activation.registerClaudeMcpServers =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
      if [ -z "$CLAUDE_BIN" ] && [ -x "$HOME/.local/bin/claude" ]; then
        CLAUDE_BIN="$HOME/.local/bin/claude"
      fi
      if [ -n "$CLAUDE_BIN" ]; then
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: json: ''
          if ! "$CLAUDE_BIN" mcp get ${name} >/dev/null 2>&1; then
            run "$CLAUDE_BIN" mcp add-json ${name} -s user '${json}'
          fi
        '') serverConfigs)}
      fi
    '';
}
