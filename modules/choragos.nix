{ pkgs, lib, config, inputs, meta, ... }:

let
  # Store-built wrapped binary (choragos-mcp-server), consumed as a flake
  # input (mirrors the ai-coding/athenaeum/cerebrum input pattern). Resolved
  # per-machine via meta.system.
  choragosPkg = inputs.choragos.packages.${meta.system}.default;

  # Same ai-coding package input already used by the machine module to seed
  # the base opencode.json — reused here as the absolute path choragos shells
  # out to (`bun run --cwd <this> pipeline plan-cycle ...`). Referencing the
  # flake input directly (rather than a hardcoded /nix/store/<hash> path)
  # means this stays in sync automatically whenever the ai-coding input is
  # updated + `home-manager switch` is run — no manual path edits.
  aiCodingPkg = inputs.ai-coding.packages.${meta.system}.default;

in
{
  # Read-only option carrying the opencode.json overlay. Machine modules read
  # this via config.programs.choragos.opencodeOverlay and fold it into their
  # single lib.recursiveUpdate before one lib.mkForce write of opencode.json.
  options.programs.choragos.opencodeOverlay = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    description = ''
      opencode.json overlay registering the choragos-mcp server over stdio.
      Exposes choragos_run_plan (deterministic ai-coding plan-cycle
      orchestrator: clean-start gate, branch, run, PR-on-green, run-ledger).
      Consumed by machine modules via lib.recursiveUpdate before the single
      lib.mkForce write of ~/.config/opencode/opencode.json.
    '';
  };

  # Per-machine default model profile. Passed as CHORAGOS_DEFAULT_PROFILE to
  # both the standalone `choragos` CLI wrapper and the MCP server registration.
  # Defaults to bedrock-sonnet so M1/M5 need no override (only AWS Bedrock
  # access is available there, no direct Anthropic API key); oryp6 overrides
  # this to opencode-free (free OpenCode Zen). A --profile flag on the command
  # line still overrides this default at runtime (the orchestrator prefers
  # RunInputs.profile over Config.default_profile).
  options.programs.choragos.defaultProfile = lib.mkOption {
    type = lib.types.str;
    default = "bedrock-sonnet";
    description = ''
      Model profile choragos passes as CHORAGOS_DEFAULT_PROFILE to the choragos
      CLI wrapper and the MCP server registration. M1/M5 keep the bedrock-sonnet
      default; oryp6 overrides to opencode-free. A runtime --profile flag wins.
    '';
  };

  config.programs.choragos.opencodeOverlay = {
    mcp = {
      choragos = {
        type = "local";
        command = [ "${choragosPkg}/bin/choragos-mcp-server" ];
        # choragos's Config::from_env() requires AI_CODING_MONOREPO,
        # CHORAGOS_DEFAULT_PROFILE, and CEREBRUM_BIN. Set explicitly rather
        # than relying on inherited shell env, since the MCP host process may
        # not carry the same environment as an interactive shell. The
        # profile comes from the per-machine programs.choragos.defaultProfile
        # option.
        environment = {
          AI_CODING_MONOREPO = "${aiCodingPkg}";
          CHORAGOS_DEFAULT_PROFILE = config.programs.choragos.defaultProfile;
          CEREBRUM_BIN = config.programs.cerebrum.binPath;
        };
        enabled = true;
        # choragos_run_plan invokes a full plan-cycle run, which can take
        # several minutes. The MCP client default request timeout (5s) would
        # abort it mid-run, so raise it well past any realistic run length.
        timeout = 600000;
      };
    };
  };

  # Expose ONLY the choragos CLI on PATH, pre-seeded with the same required env
  # vars as the MCP registration above (AI_CODING_MONOREPO,
  # CHORAGOS_DEFAULT_PROFILE, CEREBRUM_BIN) so `choragos --plan PLAN.md` works
  # standalone from any shell without the caller needing to export anything.
  # A --profile flag on the command line still overrides this default. The
  # MCP server binary is deliberately left off PATH — OpenCode launches it
  # via the absolute store path in the MCP registration. Defined here in
  # config (not the let block) so it can read
  # config.programs.choragos.defaultProfile.
  config.home.packages = [
    (pkgs.writeShellScriptBin "choragos" ''
      exec env \
        AI_CODING_MONOREPO="${aiCodingPkg}" \
        CHORAGOS_DEFAULT_PROFILE="${config.programs.choragos.defaultProfile}" \
        CEREBRUM_BIN="${config.programs.cerebrum.binPath}" \
        "${choragosPkg}/bin/choragos" "$@"
    '')
  ];
}
