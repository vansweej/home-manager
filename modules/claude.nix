{ lib, inputs, ... }:

let
  # Same raw-source pattern as opencode.nix: read agora's flake-input store
  # tree directly (no per-system build needed for plain file content).
  # To update: nix flake update agora && home-manager switch.
  claudeDir = inputs.agora;

  # ── Generated skills (Option A: committed render output) ──────────────────
  # clients/claude/generated/skills/<name>/ — produced by renderers/render.sh
  # at dev/CI time and committed to agora. 21 dirs (15 shared skills + 6
  # persona agents rendered as Claude skills), each a single SKILL.md
  # carrying a DO-NOT-EDIT provenance marker. Deployed as WHOLE dirs (see
  # nativeSkillEntries below for why) even though these are SKILL.md-only,
  # for uniform handling with native skills.
  #
  # Adding a new generated skill: handled automatically by re-running
  # renderers/render.sh in agora — no changes needed here.
  generatedDir = claudeDir + "/clients/claude/generated/skills";
  generatedSkillDirs = builtins.readDir generatedDir;
  generatedSkillEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".claude/skills/${name}"
      { source = generatedDir + "/${name}"; recursive = true; }
  ) (lib.filterAttrs (_: t: t == "directory") generatedSkillDirs);

  # ── Native skills (hand-authored, committed) ───────────────────────────────
  # clients/claude/native/{grill-me, grill-with-docs}. Deployed as WHOLE
  # dirs — NOT the SKILL.md-only pattern opencode.nix uses for its native
  # skills — because grill-with-docs ships ADR-FORMAT.md + CONTEXT-FORMAT.md
  # alongside SKILL.md; a SKILL.md-only copy would silently drop them.
  # CLAUDE.md also lives at clients/claude/native/ root as a *file*, not a
  # skill dir — readDir + filterAttrs(directory) excludes it here; it is
  # deployed separately below via home.file.
  #
  # Adding a new native skill: create agora/clients/claude/native/<name>/,
  # git add, switch.
  nativeDir = claudeDir + "/clients/claude/native";
  nativeSkillDirs = builtins.readDir nativeDir;
  nativeSkillEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".claude/skills/${name}"
      { source = nativeDir + "/${name}"; recursive = true; }
  ) (lib.filterAttrs (_: t: t == "directory") nativeSkillDirs);

in
{
  # ── Dotfiles ────────────────────────────────────────────────────────────────
  # Deploys ONLY ~/.claude/skills/<name>/ and ~/.claude/CLAUDE.md.
  #
  # CRITICAL: ~/.claude/settings.json is DELIBERATELY NOT declared here. It
  # is corporate Bedrock configuration (AWS_PROFILE, ANTHROPIC_DEFAULT_*_MODEL
  # Bedrock inference-profile ARNs, OTEL endpoints) provisioned by the
  # separate ~/.aits-claude-code-setup tool, not home-manager. Home Manager
  # only manages files it explicitly declares, so omitting settings.json here
  # is sufficient to leave it untouched.
  #
  # Model short-names emitted by the renderer (opus/sonnet) resolve via that
  # same settings.json's ANTHROPIC_DEFAULT_OPUS_MODEL / _SONNET_MODEL Bedrock
  # ARN mappings — no additional configuration needed here.
  home.file = {
    # Global Claude Code instructions — nix-store copy.
    ".claude/CLAUDE.md".source = nativeDir + "/CLAUDE.md";
  }
  // generatedSkillEntries
  // nativeSkillEntries;
}
