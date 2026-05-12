{ pkgs, lib, config, inputs, meta, ... }:

let
  opencodeDir = ../opencode;
  # The ai-coding Nix package: full source tree + node_modules, built offline
  # from the pinned flake input. Read-only in the store; bun run works fine
  # from read-only paths (verified). No git clone or bun install at activation.
  aiCodingPkg  = inputs.ai-coding.packages.${meta.system}.default;
  aiCodingRepo = "${aiCodingPkg}";

  # ── Auto-discover agents ────────────────────────────────────────────────────
  # Every .md file in opencode/agents/ is deployed as a nix-store copy.
  # Adding a new agent: drop <name>.md in opencode/agents/, git add, switch.
  agentFiles = builtins.readDir (opencodeDir + "/agents");
  agentEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/agents/${name}"
      { source = opencodeDir + "/agents/${name}"; }
  ) (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) agentFiles);

  # ── Auto-discover skills ────────────────────────────────────────────────────
  # Every subdirectory of opencode/skills/ is expected to contain a SKILL.md.
  # Adding a new skill: create opencode/skills/<name>/SKILL.md, git add, switch.
  skillDirs = builtins.readDir (opencodeDir + "/skills");
  skillEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/skills/${name}/SKILL.md"
      { source = opencodeDir + "/skills/${name}/SKILL.md"; }
  ) (lib.filterAttrs (_: t: t == "directory") skillDirs);

  # ── Auto-discover commands ──────────────────────────────────────────────────
  # Every .md file in opencode/commands/ is deployed as a nix-store copy.
  # Adding a new command: drop <name>.md in opencode/commands/, git add, switch.
  commandFiles = builtins.readDir (opencodeDir + "/commands");
  commandEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/commands/${name}"
      { source = opencodeDir + "/commands/${name}"; }
  ) (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) commandFiles);

  # ── Auto-discover tools ─────────────────────────────────────────────────────
  # Every .ts file in opencode/tools/ is deployed as a live symlink pointing
  # back into this home-manager repo. Tools use mkOutOfStoreSymlink so bun can
  # resolve node_modules from ~/.config/opencode/ at runtime.
  #
  # The source of truth for tool code is opencode/tools/ in this repo.
  # bun install runs in ~/.config/opencode/ (see installAiCodingDeps below)
  # to provide the @opencode-ai/plugin dependency.
  #
  # Adding a new tool: drop <name>.ts in opencode/tools/, git add, switch.
  toolFiles = builtins.readDir (opencodeDir + "/tools");
  toolEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/tools/${name}"
      { source = config.lib.file.mkOutOfStoreSymlink
          "${config.home.homeDirectory}/Projects/home-manager/opencode/tools/${name}"; }
  ) (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".ts" n) toolFiles);

  # ── Auto-discover CLI wrapper scripts ───────────────────────────────────────
  # Every file in opencode/bin/ is deployed to ~/.local/bin/ as a nix-store
  # copy with the executable bit set. Convention: bin/ contains only shell
  # scripts (no extension). No symlinks needed — scripts have no node_modules
  # dependency.
  #
  # Adding a new wrapper: drop <name> in opencode/bin/, git add, switch.
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
  # ~/.local/bin/ holds shell wrapper scripts deployed from opencode/bin/.
  home.sessionPath = [
    "$HOME/.opencode/bin"
    "$HOME/.local/bin"
  ];

  # ── Activation scripts ──────────────────────────────────────────────────────

  # Install dependencies for ~/.config/opencode/ (@opencode-ai/plugin, consumed
  # by the tools symlinked into ~/.config/opencode/tools/) and for the
  # home-manager opencode directory (bun resolves @opencode-ai/plugin relative
  # to the tool file's real path via the symlink chain).
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
      _oc_install "$HOME/Projects/home-manager/opencode"
    '';
}
