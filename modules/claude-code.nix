{ pkgs, lib, config, ... }:

let
  claudeDir = ../claude-code;

  # Skills that are also exposed as spawnable subagents under ~/.claude/agents/.
  # The agent file is sourced directly from the skill's SKILL.md — single source of truth.
  # To promote a new skill to an agent, add its name here.
  agentSkills = [ "brainstorm" "build" "debugger" "explore" "plan" "reviewer" "spar" "teach" "tester" ];

  agentEntries = builtins.listToAttrs (map (name: {
    name  = ".claude/agents/${name}.md";
    value = { source = claudeDir + "/skills/${name}/SKILL.md"; };
  }) agentSkills);

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
