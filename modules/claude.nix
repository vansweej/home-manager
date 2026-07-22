{ lib, inputs, ... }:

let
  # Same raw-source pattern as opencode.nix: read agora's flake-input store
  # tree directly (no per-system build needed for plain file content).
  # To update: nix flake update agora && home-manager switch.
  claudeDir = inputs.agora;

  # ── Skills (Option A: committed render output + hand-authored native) ─────
  # clients/claude/.apm/skills/<name>/ — since agora's apm migration, the 21
  # LLM-rendered skills (produced by renderers/render.sh, committed to agora)
  # and the 2 hand-authored native skills (grill-me, grill-with-docs) live
  # together in one directory: apm has no "native vs generated" distinction
  # at the primitive level, only a single skills/ namespace, so agora folded
  # them into the same clients/claude/.apm/skills/ tree during the migration.
  # Deployed as WHOLE dirs (not SKILL.md-only) so grill-with-docs' aux files
  # (ADR-FORMAT.md, CONTEXT-FORMAT.md) travel along with its SKILL.md.
  #
  # Adding a new skill: for a rendered one, re-run renderers/render.sh in
  # agora — no changes needed here. For a native one, create
  # agora/clients/claude/.apm/skills/<name>/, git add, switch.
  skillsDir = claudeDir + "/clients/claude/.apm/skills";
  skillDirs = builtins.readDir skillsDir;
  skillEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".claude/skills/${name}"
      { source = skillsDir + "/${name}"; recursive = true; }
  ) (lib.filterAttrs (_: t: t == "directory") skillDirs);

  # ── Strip apm instruction frontmatter ────────────────────────────────────────
  # CLAUDE.md is now authored as an apm `instructions` primitive
  # (clients/claude/.apm/instructions/claude.instructions.md), which requires
  # a frontmatter block (`description:`) so `apm compile` can fold it into
  # colleagues' CLAUDE.md. That frontmatter is meaningless to Claude Code's
  # own CLAUDE.md reader, so it is stripped here before deploy.
  stripFrontmatter = path:
    let
      lines = lib.splitString "\n" (builtins.readFile path);
      afterFirst = lib.lists.drop 1 lines;
      closeIdx = lib.lists.findFirstIndex (l: l == "---") null afterFirst;
      afterClose = if closeIdx == null
        then lines
        else lib.lists.drop (closeIdx + 1) afterFirst;
      withoutLeadingBlank =
        if afterClose != [ ] && builtins.head afterClose == ""
        then lib.lists.drop 1 afterClose
        else afterClose;
    in
    if builtins.head lines == "---"
    then lib.concatStringsSep "\n" withoutLeadingBlank
    else builtins.readFile path;

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
    # Global Claude Code instructions — sourced from agora's apm instruction
    # primitive with its frontmatter stripped (see stripFrontmatter above).
    ".claude/CLAUDE.md".text =
      stripFrontmatter (claudeDir + "/clients/claude/.apm/instructions/claude.instructions.md");
  }
  // skillEntries;
}
