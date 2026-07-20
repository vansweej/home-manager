{ pkgs, lib, config, inputs, meta, ... }:

let
  # The authored agents/skills/commands/bin/AGENTS.md/package.json content
  # lives in the agora flake input's source tree (github:vansweej/agora).
  # This references the flake input's raw store path directly (like the old
  # `../opencode` relative path) rather than a built package — no per-system
  # derivation build is needed for plain file content, which also avoids
  # requiring an x86_64-linux builder on darwin hosts for the oryp6 config.
  # To update: nix flake update agora && home-manager switch.
  opencodeDir = inputs.agora;

  # tools/*.ts are deployed as live mkOutOfStoreSymlinks (not nix-store
  # copies — see toolEntries below), pointing at the agora dev checkout on
  # disk so edits are picked up without a home-manager switch.
  toolsDevDir = "${config.home.homeDirectory}/Projects/agora/tools";

  # The ai-coding Nix package: full source tree + node_modules, built offline
  # from the pinned flake input. Read-only in the store; bun run works fine
  # from read-only paths (verified). No git clone or bun install at activation.
  aiCodingPkg  = inputs.ai-coding.packages.${meta.system}.default;
  aiCodingRepo = "${aiCodingPkg}";

  # ── Auto-discover agents ────────────────────────────────────────────────────
  # Every .md file in agora's agents/ is deployed as a nix-store copy.
  # Adding a new agent: drop <name>.md in agora/agents/, git add, switch.
  agentFiles = builtins.readDir (opencodeDir + "/agents");
  agentEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/agents/${name}"
      { source = opencodeDir + "/agents/${name}"; }
  ) (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) agentFiles);

  # ── Auto-discover skills ────────────────────────────────────────────────────
  # Every subdirectory of agora's skills/ is expected to contain a SKILL.md.
  # Adding a new skill: create agora/skills/<name>/SKILL.md, git add, switch.
  skillDirs = builtins.readDir (opencodeDir + "/skills");
  skillEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/skills/${name}/SKILL.md"
      { source = opencodeDir + "/skills/${name}/SKILL.md"; }
  ) (lib.filterAttrs (_: t: t == "directory") skillDirs);

  # ── Auto-discover opencode-native skills ────────────────────────────────────
  # Client-native opencode-only skills live in agora's clients/opencode/native/
  # (bypass the LLM renderer entirely — opencode IS the source format).
  # Deployed identically to shared skills, into the same
  # ~/.config/opencode/skills/ namespace.
  # Adding a new native skill: create agora/clients/opencode/native/<name>/SKILL.md, git add, switch.
  nativeSkillDirs = builtins.readDir (opencodeDir + "/clients/opencode/native");
  nativeSkillEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/skills/${name}/SKILL.md"
      { source = opencodeDir + "/clients/opencode/native/${name}/SKILL.md"; }
  ) (lib.filterAttrs (_: t: t == "directory") nativeSkillDirs);

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
  # Every .ts file in agora's tools/ is deployed as a live symlink pointing
  # back into the agora dev checkout. Tools use mkOutOfStoreSymlink so bun can
  # resolve node_modules from ~/.config/opencode/ at runtime.
  #
  # The source of truth for tool code is agora/tools/ (dev checkout at
  # ~/Projects/agora). bun install runs in ~/.config/opencode/ (see
  # installAiCodingDeps below) to provide the @opencode-ai/plugin dependency.
  #
  # Adding a new tool: drop <name>.ts in agora/tools/, git add, switch.
  toolFiles = builtins.readDir (opencodeDir + "/tools");
  toolEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/tools/${name}"
      { source = config.lib.file.mkOutOfStoreSymlink
          "${toolsDevDir}/${name}"; }
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

in
{
  # ── Dotfiles ────────────────────────────────────────────────────────────────
  home.file = {
    # Global agent instructions — nix-store copy.
    ".config/opencode/AGENTS.md".source = opencodeDir + "/AGENTS.md";

    # OpenCode config — sourced from the pinned ai-coding Nix store path.
    # To update: nix flake update ai-coding && home-manager switch.
    ".config/opencode/opencode.json".source = "${aiCodingPkg}/opencode.json";

    # Tool dependencies — nix-store copy. Provides @opencode-ai/plugin to the
    # tools symlinked into ~/.config/opencode/tools/. bun install runs against
    # this directory in the installAiCodingDeps activation step.
    # NOTE: if ~/.config/opencode/package.json already exists as a plain file,
    # remove it before running home-manager switch:
    #   rm ~/.config/opencode/package.json
    ".config/opencode/package.json".source = opencodeDir + "/package.json";
  }
  // agentEntries
  // skillEntries
  // nativeSkillEntries
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

  # ── Activation scripts ──────────────────────────────────────────────────────

  # Install dependencies for ~/.config/opencode/ (@opencode-ai/plugin, consumed
  # by the tools symlinked into ~/.config/opencode/tools/) and for the agora
  # dev checkout (bun resolves @opencode-ai/plugin relative to the tool
  # file's real path via the symlink chain).
  #
  # The ai-coding monorepo itself is now a Nix package (no clone or bun install
  # needed at activation time — node_modules are baked into the store path).
  #
  # Uses a bun.lock SHA-256 stamp to skip redundant installs — bun install
  # only runs when the lockfile has changed since the last successful install.
  home.activation.installAiCodingDeps =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      _oc_install() {
        local dir="$1"
        # Use bun.lock for change detection when available; fall back to
        # package.json so a fresh machine with no lockfile still installs.
        local lockFile="$dir/bun.lock"
        if [ ! -f "$lockFile" ]; then lockFile="$dir/package.json"; fi
        if [ ! -f "$lockFile" ]; then return 0; fi
        local lockHash
        lockHash=$(${pkgs.coreutils}/bin/sha256sum "$lockFile" | cut -d' ' -f1)
        local stamp="$dir/node_modules/.hm-install-stamp"
        # Skip if stamp matches current lockfile hash
        if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$lockHash" ]; then
          return 0
        fi
        # Install and write stamp only on success
        if $DRY_RUN_CMD ${pkgs.bun}/bin/bun install --cwd "$dir"; then
          echo "$lockHash" > "$stamp"
        fi
      }
      _oc_install "$HOME/.config/opencode"
      _oc_install "$HOME/Projects/agora"
    '';
}
