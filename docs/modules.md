# Module reference

This page describes what each module manages and what belongs where.

## `modules/common.nix` — universal

Applied to **every machine** regardless of platform or hostname.

### Packages

| Package | Purpose |
|---|---|
| `nerd-fonts.fira-code` | FiraCode Nerd Font (used by Ghostty and terminal) |
| `htop` | Interactive process viewer |
| `tree` | Directory tree printer |
| `bun` | JavaScript runtime (used by the OpenCode pipeline tool) |

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
| `~/.config/opencode/AGENTS.md` | `opencode/AGENTS.md` | Store copy |
| `~/.config/opencode/skill/*/SKILL.md` | `opencode/skill/*/SKILL.md` | Store copy |
| `~/.config/opencode/agents/*.md` | `opencode/agents/*.md` | Store copy |
| `~/.config/opencode/commands/*.md` | `opencode/commands/*.md` | Store copy |
| `~/.config/opencode/tools/pipeline.ts` | `~/Projects/ai-coding/.opencode/tools/pipeline.ts` | Live symlink |
| `~/.config/opencode/opencode.json` | `~/Projects/ai-coding/opencode/mappings/opencode.json` | Live symlink |
| `~/.config/nvim/lua/plugins/opencode.lua` | `~/Projects/home-manager/nvim/plugins/opencode.lua` | Live symlink |
| `~/.config/nvim/lua/plugins/rust.lua` | `~/Projects/home-manager/nvim/plugins/rust.lua` | Live symlink |
| `~/.config/nvim/lazyvim.json` | `~/Projects/home-manager/nvim/lazyvim.json` | Live symlink |

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
| `bootstrapNvim` | Before `writeBoundary` | Clones LazyVim starter into `~/.config/nvim` on first run; strips `.git` |

Both scripts are idempotent — they check for the target before cloning.

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

## Where to put new config

| Config type | Target file |
|---|---|
| Applies to all machines | `modules/common.nix` |
| Applies to all Linux machines | `modules/linux.nix` |
| Applies to all macOS machines | `modules/darwin.nix` |
| Applies to one specific machine | `modules/machines/<name>.nix` |
| Machine identity (username, homeDir) | `machines/<name>.nix` (metadata, not a module) |
