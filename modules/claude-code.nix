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

  # ── Auto-discover skills ────────────────────────────────────────────────────
  # Every subdirectory in claude-code/skills/ with a SKILL.md file is deployed.
  # Adding a new skill: create claude-code/skills/<name>/SKILL.md, git add, switch.
  skillDirs = builtins.readDir (claudeDir + "/skills");
  skillEntries = lib.mapAttrs' (name: type:
    lib.nameValuePair
      ".claude/skills/${name}"
      { source = claudeDir + "/skills/${name}"; }
  ) (lib.filterAttrs (n: t: t == "directory") skillDirs);

in
{
  # ── Dotfiles ────────────────────────────────────────────────────────────────
  home.file = agentEntries // skillEntries;
}
