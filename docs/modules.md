# Module reference

This page describes what each module manages and what belongs where.

## `modules/common.nix` — universal

Applied to **every machine** regardless of platform or hostname.
Imports `modules/opencode.nix` for all OpenCode configuration.

### Packages

| Package | Purpose |
|---|---|
| `nerd-fonts.fira-code` | FiraCode Nerd Font (used by Ghostty and terminal) |
| `htop` | Interactive process viewer |
| `tree` | Directory tree printer |
| `bun` | JavaScript runtime (used by the OpenCode pipeline and skill-retrieval tools) |

### Programs

| Program | Notes |
|---|---|
| `programs.bat` | `cat` replacement with syntax highlighting |
| `programs.bash` | Bash with session-vars reload fix |
| `programs.starship` | Cross-shell prompt; bash integration enabled |
| `programs.ghostty` | Terminal emulator; font: FiraCode Nerd Font; theme: Night Owl |
| `programs.git` | User: Jan Van Sweevelt / vansweej@gmail.com |
| `programs.neovim` | Default editor; aliased as `vim` and `vi` |
| `programs.home-manager` | Lets Home Manager manage itself |

### Dotfiles (`home.file`)

| Destination | Source | Method |
|---|---|---|
| `~/.config/nvim/lua/plugins/opencode.lua` | `~/Projects/home-manager/nvim/plugins/opencode.lua` | Live symlink |
| `~/.config/nvim/lua/plugins/rust.lua` | `~/Projects/home-manager/nvim/plugins/rust.lua` | Live symlink |
| `~/.config/nvim/lazyvim.json` | `~/Projects/home-manager/nvim/lazyvim.json` | Live symlink |

### Activation scripts

| Script | Trigger | Action |
|---|---|---|
| `bootstrapNvim` | Before `writeBoundary` | Clones LazyVim starter into `~/.config/nvim` on first run; strips `.git` |

---

## `modules/opencode.nix` — OpenCode configuration

Imported by `common.nix`. Manages all OpenCode configuration for every machine.

### Auto-discovery

`builtins.readDir` scans the `opencode/` directory at Nix evaluation time to
generate `home.file` entries automatically. **No manual entries are needed** when
adding new agents, skills, commands, or tools — just drop the file, `git add` it,
and run `home-manager switch`.

| Category | Source directory | Filter | Deployment method |
|---|---|---|---|
| Agents | `opencode/agents/` | `*.md` files | Nix store copy |
| Skills | `opencode/skills/` | Subdirectories (each must contain `SKILL.md`) | Nix store copy |
| Commands | `opencode/commands/` | `*.md` files | Nix store copy |
| Tools | `opencode/tools/` | `*.ts` files | `mkOutOfStoreSymlink` → home-manager repo |
| Bin wrappers | `opencode/bin/` | All files | Nix store copy, executable bit set |

**Tool deployment:** Files in `opencode/tools/` are full TypeScript implementations
deployed as live symlinks pointing to `~/Projects/home-manager/opencode/tools/`.
Using `mkOutOfStoreSymlink` (rather than a Nix store copy) lets bun resolve
`node_modules` relative to the file at runtime. The tools delegate to the
ai-coding monorepo at runtime via subprocess — they do not import code from it.

### Dotfiles (`home.file`)

| Destination | Source | Method |
|---|---|---|
| `~/.config/opencode/AGENTS.md` | `opencode/AGENTS.md` | Store copy |
| `~/.config/opencode/skills/*/SKILL.md` | `opencode/skills/*/SKILL.md` | Store copy (auto-discovered) |
| `~/.config/opencode/agents/*.md` | `opencode/agents/*.md` | Store copy (auto-discovered) |
| `~/.config/opencode/commands/*.md` | `opencode/commands/*.md` | Store copy (auto-discovered) |
| `~/.config/opencode/tools/pipeline.ts` | `~/Projects/home-manager/opencode/tools/pipeline.ts` | Live symlink (auto-discovered) |
| `~/.config/opencode/tools/skill-retrieval.ts` | `~/Projects/home-manager/opencode/tools/skill-retrieval.ts` | Live symlink (auto-discovered) |
| `~/.config/opencode/tools/codebase-retrieval.ts` | `~/Projects/home-manager/opencode/tools/codebase-retrieval.ts` | Live symlink (auto-discovered) |
| `~/.config/opencode/opencode.json` | ai-coding Nix store path (`opencode.json`) | Store copy |
| `~/.local/bin/codebase-retrieval` | `opencode/bin/codebase-retrieval` | Store copy, executable (auto-discovered) |
| `~/.local/bin/index-codebase` | `opencode/bin/index-codebase` | Store copy, executable (auto-discovered) |

### Session variables

| Variable | Value |
|---|---|
| `AI_CODING_MONOREPO` | Nix store path of the ai-coding package (set from `inputs.ai-coding.packages.${system}.default`) |

### Session path

- `$HOME/.opencode/bin`
- `$HOME/.local/bin`

### Activation scripts

| Script | Trigger | Action |
|---|---|---|
| `installAiCodingDeps` | After `writeBoundary` | Installs `@opencode-ai/plugin` in `~/.config/opencode/` and `~/Projects/home-manager/opencode/` with stamp-based skip |

#### `installAiCodingDeps` — stamp-based install

Runs `bun install` in `~/.config/opencode/` (provides `@opencode-ai/plugin` to the
OpenCode tools symlinked there) and `~/Projects/home-manager/opencode/` (same
dependency, resolved via the symlink chain at runtime).

The ai-coding monorepo itself is a Nix package — `node_modules` are baked into the
store at build time. No `bun install` is needed for it at activation.

A SHA-256 hash of `bun.lock` is stored in `node_modules/.hm-install-stamp`.
On subsequent switches the stamp is compared to the current lockfile — if they
match, install is skipped. The stamp is written **only on success**, so a failed
install leaves no stamp and is retried on the next switch.

---

## `modules/athenaeum.nix` — athenaeum-mcp server overlay

Imported by **oryp6, M5, M1** (but not parallels or parallels-ubuntu). Does not write any
files — it is a data-only module that declares and assigns the
`programs.athenaeum.opencodeOverlay` option, which machine modules consume.

### What the overlay contains

| Key | Value | Description |
|---|---|---|
| `mcp.athenaeum` | MCP server block | Registers the `athenaeum-mcp-server` as a `type: "local"` server launched via `nix develop … cargo run -p athenaeum-mcp-server` with `cwd` pinned to the repo root (so the relative `./data/athenaeum` db_path resolves correctly) |
| `tools."athenaeum*"` | `false` | Disables the server's tools globally |
| `agent.brainstorm.tools."athenaeum*"` | `true` | Enables for brainstorm |
| `agent.spar.tools."athenaeum*"` | `true` | Enables for spar |
| `agent.teach.tools."athenaeum*"` | `true` | Enables for teach |
| `agent.plan.tools."athenaeum*"` | `true` | Enables for plan |

The server's `command` array resolves the repo path from `config.home.homeDirectory`
so it works on both Linux (`/home/vansweej`) and macOS (`/Users/janvansweevelt`).

### Design invariant

This module does **not** set `home.file` for `opencode.json`. Each consuming
machine performs exactly one `lib.recursiveUpdate` + one `lib.mkForce` write,
which allows M5 to fold the athenaeum overlay into the **same merge** as its
existing Ollama provider without a conflicting second definition.

### Corpus watcher options

| Option | Type | Description |
|---|---|---|
| `programs.athenaeum.watchDir` | str (default `~/Documents/corpus`) | Non-hidden corpus directory watched for PDF/EPUB changes |
| `programs.athenaeum.watchCommand` | str (read-only) | Resolved `watchexec` command; consumed by per-machine service units |

`watchCommand` runs `watchexec` with `--watch <watchDir>`, `--workdir <dataDir>`
(so the CLI's relative `./data/athenaeum` db_path resolves to the shared store),
`--postpone` (no reingest at startup), `--debounce 5s`, and `--on-busy-update queue`.
`watchexec` is added to `home.packages` here. The actual service unit is registered
per-machine (systemd on oryp6, launchd on M1/M5), each pinning its working directory
to `dataDir` as a second cwd guarantee.

---

## `modules/linux.nix` — Linux only

Applied to all Linux machines (`x86_64-linux` and `aarch64-linux`).

### Packages

| Package | Purpose |
|---|---|
| `nixgl.nixGLIntel` | OpenGL wrapper required for GPU apps outside NixOS — only installed when `meta.nixGL = true` |
| `ghostty-nixgl` | Shell script that runs `ghostty` via `nixGLIntel` — only when `meta.nixGL = true` |

The nixGL wrapper and `.desktop` file are guarded by `meta.nixGL`. Machines that
don't need it (e.g. `parallels-ubuntu`) set no `nixGL` field and get neither.

### Dotfiles

| Destination | Content |
|---|---|
| `~/.local/share/applications/ghostty-nixgl.desktop` | freedesktop.org `.desktop` entry so Ghostty appears in application launchers |

---

## `modules/darwin.nix` — macOS only

Applied to all `aarch64-darwin` machines.

Currently a placeholder. Add macOS-wide config here when it emerges — for example,
macOS defaults (`defaults write`), or Homebrew integration.
A concrete `launchd.agents` example (the athenaeum corpus watcher) now exists in
`modules/machines/m1.nix` and `modules/machines/m5.nix` — machine-specific agents
belong in the machine module, not here.

Do **not** add machine-specific config here — that belongs in
`modules/machines/<name>.nix`.

---

## `modules/machines/oryp6.nix` — oryp6 only

Applied only to the `oryp6` profile (`x86_64-linux`, username `vansweej`).

Overrides `opencode.json` by merging the athenaeum-mcp overlay from
`modules/athenaeum.nix` onto the upstream ai-coding config via
`lib.recursiveUpdate` + `lib.mkForce`.

### Packages

| Package | Purpose |
|---|---|
| `docker` | Container runtime |
| `slirp4netns` | Rootless Docker networking |
| `rootlesskit` | Rootless Docker helper |

### Session variables

| Variable | Value |
|---|---|
| `DOCKER_HOST` | `unix:///run/user/1000/docker.sock` |

### Services

| Service | Type | Notes |
|---|---|---|
| `docker` | `systemd.user.services` | Runs `dockerd-rootless`; starts on `default.target` |
| `athenaeum-watch` | `systemd.user.services` | Runs `watchexec`; reingests `~/Documents/corpus` on change; `Restart = "always"` |

---

## `modules/machines/m1.nix` — M1 MacBook only

Applied only to the `M1` profile (`aarch64-darwin`, username `janvansweevelt`).

Overrides `opencode.json` by merging the athenaeum-mcp overlay from
`modules/athenaeum.nix` onto the upstream ai-coding config via
`lib.recursiveUpdate` + `lib.mkForce`. Registers `launchd.agents.athenaeum-watch`
(the corpus watcher). Otherwise has no machine-specific packages.

---

## `modules/machines/m5.nix` — M5 MacBook only

Applied only to the `M5` profile (`aarch64-darwin`, username `janvansweevelt`).

Overrides three shared defaults with M5-specific values:

- **`opencode.json`** — reads the upstream config from the `aiCodingPkg` Nix
  store path via `builtins.fromJSON`, then uses nested `lib.recursiveUpdate` to
  inject **both** the Ollama provider (`gemma4:26b`) and the athenaeum-mcp
  overlay from `modules/athenaeum.nix` in a single merge. The two overlays touch
  disjoint top-level keys (`provider.*` vs `mcp.*` / `tools.*` / `agent.*`), so
  there is no collision. All other settings — model, compaction, and permissions
  — are inherited from `ai-coding/opencode.json` unchanged.

  > **`lib.recursiveUpdate` note:** merges attrsets deeply but replaces lists
  > wholesale. The current schema has no lists at overlapping keys, so there is
  > no collision risk. If that changes, revisit the merge strategy.

- **`local.md` agent** — replaces the shared local agent with an M5-specific
  version whose frontmatter sets `model: ollama/gemma4:26b`.
- **`launchd.agents.athenaeum-watch`** — registers the corpus watcher (logs to
  `~/.local/share/athenaeum/watch.log`).

---

## `modules/machines/parallels-ubuntu.nix` — Parallels Ubuntu VM only

Applied only to the `parallels-ubuntu` profile (`aarch64-linux`, username `parallels`).

Currently a placeholder. Used as a test bed for the Nix flake-based ai-coding
setup on `aarch64-linux` before promoting changes to M5 and oryp6.

---

## Where to put new config

| Config type | Target file |
|---|---|
| Applies to all machines | `modules/common.nix` |
| OpenCode agents, skills, commands, tools | `opencode/<category>/` + `git add` (auto-discovered) |
| Applies to all Linux machines | `modules/linux.nix` |
| Applies to all macOS machines | `modules/darwin.nix` |
| Applies to a subset of machines (e.g. oryp6, M5, M1) | Shared module (e.g. `modules/athenaeum.nix`) + imported by each machine's `modules/machines/<name>.nix` |
| Applies to one specific machine | `modules/machines/<name>.nix` |
| Machine identity (username, homeDir) | `machines/<name>.nix` (metadata, not a module) |
