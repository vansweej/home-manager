{ lib, inputs, meta, config, ... }:

let
  # Store-built cerebrum binary. The binary self-locates its LanceDB store
  # in-binary (crates/cerebrum-core/src/config.rs's default_data_dir: XDG_DATA_HOME,
  # else HOME/.local/share, resolving to ~/.local/share/cerebrum/data/cerebrum by
  # default), so this module needs no dataDir option, no activation mkdir, and no
  # cwd in the MCP registration — packages.default is the bare binary directly
  # (the former cd-wrapping cerebrum-wrapped shell script has been removed
  # upstream now that it's redundant). The shipped binary uses real Ollama
  # embeddings (lazy-initialized on first remember/recall call).
  cerebrumPkg = inputs.cerebrum.packages.${meta.system}.default;
in
{
  # Single source of truth for the absolute store path to the cerebrum binary.
  # readOnly: its value is fixed to "${cerebrumPkg}/bin/cerebrum" by this module.
  # Consumed by choragos.nix (MCP env + CLI wrapper) and claude-mcp.nix
  # (cerebrum-mcp + choragos-mcp wrappers) via config.programs.cerebrum.binPath,
  # eliminating duplicated store-path derivations. Also exported to interactive
  # login shells as CEREBRUM_BIN (below) so a raw pipeline invocation
  # (`bun run … pipeline plan-cycle … --plan-ref …`) can resolve --plan-ref
  # without going through the choragos CLI wrapper that pre-seeds it.
  # The bare binary is deliberately NOT on PATH; consumers must use this
  # absolute store path.
  options.programs.cerebrum.binPath = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    description = ''
      Absolute /nix/store path to the cerebrum binary
      ("''${cerebrumPkg}/bin/cerebrum"). Single source of truth consumed by
      choragos.nix, claude-mcp.nix, and the CEREBRUM_BIN session variable.
    '';
  };

  # Read-only option carrying the opencode.json overlay. Machine modules read
  # this via config.programs.cerebrum.opencodeOverlay and fold it into their
  # single lib.recursiveUpdate before one lib.mkForce write of opencode.json.
  options.programs.cerebrum.opencodeOverlay = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    description = ''
      opencode.json overlay registering the cerebrum-mcp memory server over
      stdio. Tools (cerebrum_remember/recall/memorize/forget/end_session/
      recall_by_scope) are enabled for ALL agents — no tool gating.
      Consumed by machine modules via lib.recursiveUpdate before the single
      lib.mkForce write of ~/.config/opencode/opencode.json.
    '';
  };

  config.programs.cerebrum.binPath = "${cerebrumPkg}/bin/cerebrum";

  # Expose the cerebrum binary path to interactive login shells so a raw
  # `bun run … pipeline …` invocation (outside the choragos MCP/CLI wrappers,
  # which set CEREBRUM_BIN themselves) can resolve --plan-ref. Home-Manager
  # writes this into hm-session-vars.sh, sourced by login shells on every host
  # importing this module (oryp6, m1, m5) — no per-host edits needed.
  config.home.sessionVariables.CEREBRUM_BIN = config.programs.cerebrum.binPath;

  # Also export the table/model/dim triple to interactive login shells, for
  # the same reason: any raw CLI invocation of $CEREBRUM_BIN (e.g. choragos's
  # own plan-ref resolution, or a manual `cerebrum-reembed` run) previously
  # ran on Config::default() alone, disagreeing with the MCP wrapper's
  # `environment` block below. As of cerebrum-mcp ADR 0002 the compiled
  # default already matches these values (memories_qwen3 / qwen3-embedding:0.6b
  # / 1024), so this export is now redundant-but-explicit belt-and-suspenders:
  # it keeps the session-variable and the MCP wrapper's environment block as
  # a single documented source of truth rather than relying on the compiled
  # default alone, and it means `echo $CEREBRUM_TABLE_NAME` in an interactive
  # shell tells the truth. All three hosts importing this module (oryp6, m1,
  # m5) have been migrated to memories_qwen3 via cerebrum-reembed.
  config.home.sessionVariables.CEREBRUM_TABLE_NAME = "memories_qwen3";
  config.home.sessionVariables.CEREBRUM_EMBED_MODEL = "qwen3-embedding:0.6b";
  config.home.sessionVariables.CEREBRUM_EMBEDDING_DIM = "1024";

  config.programs.cerebrum.opencodeOverlay = {
    mcp = {
      cerebrum = {
        type = "local";
        command = [ "${cerebrumPkg}/bin/cerebrum" ];
        environment = {
          CEREBRUM_TABLE_NAME = "memories_qwen3";
          CEREBRUM_EMBED_MODEL = "qwen3-embedding:0.6b";
          CEREBRUM_EMBEDDING_DIM = "1024";
        };
        enabled = true;
      };
    };

    # Agents that carry a per-agent `tools` allowlist (added by athenaeum.nix)
    # do not inherit MCP tools that are absent from that list — so cerebrum
    # silently drops off them, even though it is globally enabled. Re-assert
    # cerebrum on each such agent. recursiveUpdate deep-merges these into the
    # athenaeum `tools` maps (cerebrum is applied last in every machine module),
    # yielding e.g. explore.tools = { "athenaeum*" = true; "cerebrum*" = true; }.
    # Agents without a `tools` block (e.g. build) already get cerebrum by default.
    agent = {
      coordinator = { tools = { "cerebrum*" = true; }; };
      brainstorm = { tools = { "cerebrum*" = true; }; };
      spar       = { tools = { "cerebrum*" = true; }; };
      teach      = { tools = { "cerebrum*" = true; }; };
      plan       = { tools = { "cerebrum*" = true; }; };
      explore    = { tools = { "cerebrum*" = true; }; };
    };
  };
}
