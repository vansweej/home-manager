{ pkgs, lib, config, ... }:

let
  opencodeDir  = ../opencode;
  aiCodingRepo = "${config.home.homeDirectory}/Projects/ai-coding";

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

in
{
  # ── Dotfiles ────────────────────────────────────────────────────────────────
  home.file = {
    # Global agent instructions — nix-store copy.
    ".config/opencode/AGENTS.md".source = opencodeDir + "/AGENTS.md";

    # OpenCode config — live symlink so edits in the ai-coding repo are
    # reflected immediately without re-running home-manager switch.
    ".config/opencode/opencode.json".source =
      config.lib.file.mkOutOfStoreSymlink
        "${aiCodingRepo}/opencode/mappings/opencode.json";

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
  // toolEntries;

  # ── Environment ─────────────────────────────────────────────────────────────
  # AI_CODING_MONOREPO: absolute path used by pipeline commands and the
  # skill-retrieval tool so they work from any project directory.
  home.sessionVariables = {
    AI_CODING_MONOREPO = aiCodingRepo;
  };

  # OpenCode installs its own CLI tools here.
  home.sessionPath = [
    "$HOME/.opencode/bin"
  ];

  # ── Activation scripts ──────────────────────────────────────────────────────

  # Clone the ai-coding repo on first activation if it is not already present.
  # Runs BEFORE writeBoundary so that mkOutOfStoreSymlink entries pointing into
  # ~/Projects/ai-coding/ are never dangling on a fresh machine.
  home.activation.cloneAiCoding = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    if [ ! -d "$HOME/Projects/ai-coding" ]; then
      $DRY_RUN_CMD mkdir -p "$HOME/Projects"
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone \
        https://github.com/vansweej/ai-coding.git \
        "$HOME/Projects/ai-coding"
    fi
  '';

  # Install dependencies for both the monorepo root (@ai-coding/skills and
  # other workspace packages) and ~/.config/opencode/ (@opencode-ai/plugin).
  #
  # Uses a bun.lock SHA-256 stamp to skip redundant installs — bun install
  # only runs when the lockfile has changed since the last successful install.
  #
  # The stamp is written ONLY on success, so a failed install (e.g. network
  # down, native binary unavailable) leaves no stamp and will be retried on
  # the next home-manager switch.
  #
  # bun install is wrapped with an if/then so failures degrade gracefully:
  # tools won't work until the next successful switch, but all other config
  # (agents, skills, shell, nvim) is still deployed.
  home.activation.installAiCodingDeps =
    lib.hm.dag.entryBetween [ "writeBoundary" ] [ "cloneAiCoding" ] ''
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
      _oc_install "$HOME/Projects/ai-coding"
      _oc_install "$HOME/.config/opencode"
      _oc_install "$HOME/Projects/home-manager/opencode"
    '';
}
