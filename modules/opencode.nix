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
  # Every subdirectory of opencode/skill/ is expected to contain a SKILL.md.
  # Adding a new skill: create opencode/skill/<name>/SKILL.md, git add, switch.
  skillDirs = builtins.readDir (opencodeDir + "/skill");
  skillEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/skill/${name}/SKILL.md"
      { source = opencodeDir + "/skill/${name}/SKILL.md"; }
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
  # Every .ts file in opencode/tools/ is deployed as a live symlink into the
  # ai-coding repo. Tools use mkOutOfStoreSymlink so bun can resolve
  # node_modules relative to the file at runtime.
  #
  # The files in opencode/tools/ are MARKER FILES only — they exist so
  # builtins.readDir can register them. The ai-coding repo is the authoritative
  # source. Do not add real source code to the home-manager copies.
  #
  # Adding a new tool: drop a marker <name>.ts in opencode/tools/, git add,
  # switch. The real implementation lives in ai-coding/.opencode/tools/<name>.ts.
  toolFiles = builtins.readDir (opencodeDir + "/tools");
  toolEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/tools/${name}"
      { source = config.lib.file.mkOutOfStoreSymlink
          "${aiCodingRepo}/.opencode/tools/${name}"; }
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
  # other workspace packages) and .opencode/ (@opencode-ai/plugin).
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
        # Skip if no lockfile — guard against missing .opencode/bun.lock
        if [ ! -f "$dir/bun.lock" ]; then return 0; fi
        local lockHash
        lockHash=$(${pkgs.coreutils}/bin/sha256sum "$dir/bun.lock" | cut -d' ' -f1)
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
      _oc_install "$HOME/Projects/ai-coding/.opencode"
    '';
}
