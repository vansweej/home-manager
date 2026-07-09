{ lib, inputs, meta, ... }:

let
  # Store-built wrapped binary (named `cerebrum`). The wrapper creates and cd's
  # into ~/.local/share/cerebrum itself, so this module needs no dataDir option,
  # no activation mkdir, and no cwd in the MCP registration. The shipped binary
  # uses real Ollama embeddings (lazy-initialized on first remember/recall call).
  cerebrumPkg = inputs.cerebrum.packages.${meta.system}.default;
in
{
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

  config.programs.cerebrum.opencodeOverlay = {
    mcp = {
      cerebrum = {
        type = "local";
        command = [ "${cerebrumPkg}/bin/cerebrum" ];
        enabled = true;
      };
    };
  };
}
