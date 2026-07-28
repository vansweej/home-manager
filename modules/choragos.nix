{ lib, inputs, meta, ... }:

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

  config.programs.choragos.opencodeOverlay = {
    mcp = {
      choragos = {
        type = "local";
        command = [ "${choragosPkg}/bin/choragos-mcp-server" ];
        # choragos's Config::from_env() requires AI_CODING_MONOREPO and
        # CHORAGOS_DEFAULT_PROFILE. Set explicitly rather than relying on
        # inherited shell env, since the MCP host process may not carry the
        # same environment as an interactive shell.
        # CHORAGOS_DEFAULT_PROFILE is "bedrock-sonnet" because Philips only
        # provides AWS Bedrock access (no direct Anthropic API key).
        environment = {
          AI_CODING_MONOREPO = "${aiCodingPkg}";
          CHORAGOS_DEFAULT_PROFILE = "bedrock-sonnet";
        };
        enabled = true;
        # choragos_run_plan invokes a full plan-cycle run, which can take
        # several minutes. The MCP client default request timeout (5s) would
        # abort it mid-run, so raise it well past any realistic run length.
        timeout = 600000;
      };
    };
  };
}
