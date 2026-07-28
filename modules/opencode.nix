{ lib, inputs, meta, ... }:

let
  # The authored agents/skills/commands/bin/AGENTS.md/package.json content
  # lives in the agora flake input's source tree (github:vansweej/agora).
  # This references the flake input's raw store path directly (like the old
  # `../opencode` relative path) rather than a built package — no per-system
  # derivation build is needed for plain file content, which also avoids
  # requiring an x86_64-linux builder on darwin hosts for the oryp6 config.
  # To update: nix flake update agora && home-manager switch.
  opencodeDir = inputs.agora;

  # The ai-coding Nix package: full source tree + node_modules, built offline
  # from the pinned flake input. Read-only in the store; bun run works fine
  # from read-only paths (verified). No git clone or bun install at activation.
  aiCodingPkg  = inputs.ai-coding.packages.${meta.system}.default;
  aiCodingRepo = "${aiCodingPkg}";

  # ── Auto-discover agents ────────────────────────────────────────────────────
  # Agora's OpenCode agents now live under the apm-native .apm/agents/
  # layout (agora migrated to apm packages — see agora/docs/architecture.md).
  # Files are named <name>.agent.md there (apm's agent primitive convention);
  # OpenCode itself expects a plain <name>.md, so the suffix is rewritten on
  # deploy. Adding a new agent: drop <name>.agent.md in agora/.apm/agents/,
  # git add, switch.
  agentFiles = builtins.readDir (opencodeDir + "/.apm/agents");
  agentEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/agents/${lib.removeSuffix ".agent.md" name}.md"
      { source = opencodeDir + "/.apm/agents/${name}"; }
  ) (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".agent.md" n) agentFiles);

  # ── Auto-discover skills ────────────────────────────────────────────────────
  # Every subdirectory of agora's .apm/skills/ is expected to contain a
  # SKILL.md. This now includes what used to be the separate
  # clients/opencode/native/ tree (e.g. context-audit) — apm has no concept
  # of a client-native skill subdirectory, so agora folded it into the same
  # .apm/skills/ namespace during the apm migration; there is nothing
  # client-specific left to discover separately here.
  # Adding a new skill: create agora/.apm/skills/<name>/SKILL.md, git add, switch.
  skillDirs = builtins.readDir (opencodeDir + "/.apm/skills");
  skillEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/skills/${name}/SKILL.md"
      { source = opencodeDir + "/.apm/skills/${name}/SKILL.md"; }
  ) (lib.filterAttrs (_: t: t == "directory") skillDirs);

  # ── Auto-discover commands ──────────────────────────────────────────────────
  # Every .md file in agora's commands/ is deployed as a nix-store copy.
  # Adding a new command: drop <name>.md in agora/commands/, git add, switch.
  commandFiles = builtins.readDir (opencodeDir + "/commands");
  commandEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/commands/${name}"
      { source = opencodeDir + "/commands/${name}"; }
  ) (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) commandFiles);

  # ── Auto-discover tools ─────────────────────────────────────────────────────
  # Every .ts file in agora's tools/ is deployed as a nix-store symlink, same
  # as commands/bin below — no on-disk agora checkout required on any
  # machine. OpenCode discovers tools by globbing `{tool,tools}/*.{js,ts}`
  # relative to each config directory (following symlinks) and imports them
  # by that config-dir path, not by the symlink's realpath target; it then
  # auto-installs `@opencode-ai/plugin` into that same config directory's
  # own `node_modules` (see OpenCode's tool/registry.ts + config/config.ts).
  # So the tool file's on-disk location is irrelevant to dependency
  # resolution — a store symlink resolves identically to a dev-checkout one.
  #
  # Trade-off: editing a tool now requires a commit to agora + `nix flake
  # update agora` + `home-manager switch` (same as agents/skills), not a
  # live edit-in-place.
  #
  # Adding a new tool: drop <name>.ts in agora/tools/, git add, switch.
  toolFiles = builtins.readDir (opencodeDir + "/tools");
  toolEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/tools/${name}"
      { source = opencodeDir + "/tools/${name}"; }
  ) (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".ts" n) toolFiles);

  # ── Auto-discover CLI wrapper scripts ───────────────────────────────────────
  # Every file in agora's bin/ is deployed to ~/.local/bin/ as a nix-store
  # copy with the executable bit set. Convention: bin/ contains only shell
  # scripts (no extension). No symlinks needed — scripts have no node_modules
  # dependency.
  #
  # Adding a new wrapper: drop <name> in agora/bin/, git add, switch.
  binFiles = builtins.readDir (opencodeDir + "/bin");
  binEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".local/bin/${name}"
      { source = opencodeDir + "/bin/${name}";
        executable = true; }
  ) (lib.filterAttrs (_: t: t == "regular") binFiles);

  # ── Strip apm instruction frontmatter ────────────────────────────────────────
  # Agora's AGENTS.md is now authored as an apm `instructions` primitive
  # (agora/.apm/instructions/agents.instructions.md), which requires a
  # frontmatter block (`description:`) so `apm compile` can fold it into
  # colleagues' AGENTS.md. That frontmatter is meaningless to OpenCode's own
  # AGENTS.md reader, so it is stripped here before deploy — a pure
  # string-processing step (no derivation), keeping this file plain-text
  # content the same way it always was on Jan's machines.
  #
  # Frontmatter is a leading `---` line, everything up to the next `---`
  # line, then a blank separator line — stripped by dropping every line up
  # to and including that second `---`, plus one following blank line.
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
  home.file = {
    # Global agent instructions — sourced from agora's apm instruction
    # primitive with its frontmatter stripped (see stripFrontmatter above).
    ".config/opencode/AGENTS.md".text =
      stripFrontmatter (opencodeDir + "/.apm/instructions/agents.instructions.md");

    # OpenCode config — sourced from the pinned ai-coding Nix store path.
    # To update: nix flake update ai-coding && home-manager switch.
    ".config/opencode/opencode.json".source = "${aiCodingPkg}/opencode.json";
  }
  // agentEntries
  // skillEntries
  // commandEntries
  // toolEntries
  // binEntries;

  # ── Environment ─────────────────────────────────────────────────────────────
  # AI_CODING_MONOREPO: absolute path used by pipeline commands and the
  # skill-retrieval tool so they work from any project directory.
  home.sessionVariables = {
    AI_CODING_MONOREPO = aiCodingRepo;
  };

  # OpenCode installs its own CLI tools here.
  # ~/.local/bin/ holds shell wrapper scripts deployed from agora's bin/.
  home.sessionPath = [
    "$HOME/.opencode/bin"
    "$HOME/.local/bin"
  ];
}
