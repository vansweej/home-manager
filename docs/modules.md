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
| Skills | `opencode/skill/` | Subdirectories (each must contain `SKILL.md`) | Nix store copy |
| Commands | `opencode/commands/` | `*.md` files | Nix store copy |
| Tools | `opencode/tools/` | `*.ts` files | `mkOutOfStoreSymlink` → ai-coding repo |

**Tool marker convention:** Files in `opencode/tools/` are marker files only.
The ai-coding repo (`~/Projects/ai-coding/.opencode/tools/`) is the authoritative
source. Markers exist so `builtins.readDir` can register the tool for deployment.
At runtime, `~/.config/opencode/tools/<name>.ts` is a live symlink into the
ai-coding repo, so bun can resolve `node_modules` relative to the file.

### Dotfiles (`home.file`)

| Destination | Source | Method |
|---|---|---|
| `~/.config/opencode/AGENTS.md` | `opencode/AGENTS.md` | Store copy |
| `~/.config/opencode/skill/*/SKILL.md` | `opencode/skill/*/SKILL.md` | Store copy (auto-discovered) |
| `~/.config/opencode/agents/*.md` | `opencode/agents/*.md` | Store copy (auto-discovered) |
| `~/.config/opencode/commands/*.md` | `opencode/commands/*.md` | Store copy (auto-discovered) |
| `~/.config/opencode/tools/pipeline.ts` | `~/Projects/ai-coding/.opencode/tools/pipeline.ts` | Live symlink (auto-discovered) |
| `~/.config/opencode/tools/skill-retrieval.ts` | `~/Projects/ai-coding/.opencode/tools/skill-retrieval.ts` | Live symlink (auto-discovered) |
| `~/.config/opencode/opencode.json` | `~/Projects/ai-coding/opencode/mappings/opencode.json` | Live symlink |

### Session variables

| Variable | Value |
|---|---|
| `AI_CODING_MONOREPO` | `$HOME/Projects/ai-coding` |

### Session path

- `$HOME/.opencode/bin`

### Activation scripts

| Script | Trigger | Action |
|---|---|---|
| `cloneAiCoding` | Before `writeBoundary` | Clones `ai-coding` repo into `~/Projects/ai-coding` on first run |
| `installAiCodingDeps` | After `cloneAiCoding`, before `writeBoundary` | Installs monorepo root and `.opencode/` dependencies with stamp-based skip |

#### `installAiCodingDeps` — stamp-based install

Runs `bun install` in both `~/Projects/ai-coding` (monorepo root, installs
`@ai-coding/skills` and other workspace packages) and
`~/Projects/ai-coding/.opencode` (installs `@opencode-ai/plugin`).

A SHA-256 hash of `bun.lock` is stored in `node_modules/.hm-install-stamp`.
On subsequent switches the stamp is compared to the current lockfile — if they
match, install is skipped. The stamp is written **only on success**, so a failed
install (network down, native binary unavailable) leaves no stamp and is retried
on the next switch. A failed install degrades gracefully: tools won't work until
the next successful switch, but all other config is still deployed.

---

## `modules/linux.nix` — Linux only

Applied to all `x86_64-linux` machines.

### Packages

| Package | Purpose |
|---|---|
| `nixgl.nixGLIntel` | OpenGL wrapper required for GPU apps outside NixOS |
| `ghostty-nixgl` | Shell script that runs `ghostty` via `nixGLIntel` |

### Dotfiles

| Destination | Content |
|---|---|
| `~/.local/share/applications/ghostty-nixgl.desktop` | freedesktop.org `.desktop` entry so Ghostty appears in application launchers |

---

## `modules/darwin.nix` — macOS only

Applied to all `aarch64-darwin` machines.

Currently a placeholder. Add macOS-wide config here when it emerges — for example,
`launchd` agents, macOS defaults (`defaults write`), or Homebrew integration.

Do **not** add machine-specific config here — that belongs in
`modules/machines/<name>.nix`.

---

## `modules/machines/oryp6.nix` — oryp6 only

Applied only to the `oryp6` profile (`x86_64-linux`, username `vansweej`).

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

---

## `modules/machines/m1.nix` — M1 MacBook only

Applied only to the `M1` profile (`aarch64-darwin`, username `janvansweevelt`).

Currently a placeholder. Add M1-specific packages and settings here as needed.

---

## `modules/machines/m5.nix` — M5 MacBook only

Applied only to the `M5` profile (`aarch64-darwin`, username `janvansweevelt`).

Currently a placeholder. Add M5-specific packages and settings here as needed —
for example, local model tooling (ollama, llama.cpp, MLX).

---

## Where to put new config

| Config type | Target file |
|---|---|
| Applies to all machines | `modules/common.nix` |
| OpenCode agents, skills, commands, tools | `opencode/<category>/` + `git add` (auto-discovered) |
| Applies to all Linux machines | `modules/linux.nix` |
| Applies to all macOS machines | `modules/darwin.nix` |
| Applies to one specific machine | `modules/machines/<name>.nix` |
| Machine identity (username, homeDir) | `machines/<name>.nix` (metadata, not a module) |
