{ pkgs, lib, config, ... }:

let
  claudeDir = ../claude-code;

  # ── Auto-discover agents ────────────────────────────────────────────────────
  # Every .md file in claude-code/agents/ is deployed as a nix-store copy.
  # Adding a new agent: drop <name>.md in claude-code/agents/, git add, switch.
  agentFiles = builtins.readDir (claudeDir + "/agents");
  agentEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".claude/agents/${name}"
      { source = claudeDir + "/agents/${name}"; }
  ) (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) agentFiles);

in
{
  # ── Dotfiles ────────────────────────────────────────────────────────────────
  home.file = agentEntries;
}
