# home-manager

Personal [Home Manager](https://github.com/nix-community/home-manager) configuration for `oryp6` (x86_64-linux).

## What this manages

- **Packages**: ghostty, neovim, bat, starship, bun, docker, git, tree, fonts
- **Neovim**: custom plugin files (`opencode.lua`, `rust.lua`, `lazyvim.json`) symlinked into `~/.config/nvim/`. LazyVim boilerplate is bootstrapped automatically (see below).
- **OpenCode**: provider config, agent profiles (local, debugger), and skill definitions
- **Shell**: bash + starship prompt
- **Docker**: rootless daemon via systemd user service
- **Activation**: clones `ai-coding` repo on first run if not present

## Fresh machine setup

### Prerequisites

- Nix installed with flakes enabled
- Home Manager installed (`nix-channel` or standalone)
- SSH key added to GitHub (for the clone step)

### Steps

```bash
# 1. Clone this repo
git clone git@github.com:vansweej/home-manager.git ~/Projects/home-manager

# 2. Run home-manager switch
#    This will:
#      - Install all packages
#      - Bootstrap ~/.config/nvim from the LazyVim starter (strips .git)
#      - Symlink nvim plugin files from this repo into ~/.config/nvim/
#      - Symlink OpenCode config files
#      - Clone the ai-coding repo into ~/Projects/ai-coding
home-manager switch --flake ~/Projects/home-manager#oryp6

# 3. Open Neovim -- LazyVim bootstraps lazy.nvim and all plugins automatically
nvim
```

That's it. No manual cloning of LazyVim or plugin setup required.

## Editing Neovim config

Custom plugin files live in `nvim/plugins/`. Edits are reflected in Neovim immediately -- no need to re-run `home-manager switch`.

```
nvim/
  plugins/
    opencode.lua   -- OpenCode integration (prompts, contexts, keymaps)
    rust.lua       -- Rust LSP config (disables mason for rust_analyzer)
  lazyvim.json     -- LazyVim extras selection
```

LazyVim boilerplate (`init.lua`, `lua/config/*.lua`) lives in `~/.config/nvim/` as unmanaged plain files and is not tracked here.

## Editing OpenCode config

OpenCode files live in `opencode/`:

```
opencode/
  AGENTS.md              -- global coding rules injected into every session
  agents/
    planner.md           -- planning agent (copilot/claude-sonnet-4.6)
    debugger.md          -- debugging agent (github-copilot/claude-sonnet-4.6)
  skill/
    analyst/SKILL.md
    architect/SKILL.md
    documenter/SKILL.md
    programmer/SKILL.md
    reviewer/SKILL.md
    tester/SKILL.md
```

The `opencode.json` provider config lives in `~/Projects/ai-coding/opencode/mappings/opencode.json` and is symlinked from there (separate repo, live edits).

## Applying changes

After editing `home.nix` or any file managed by the Nix store (i.e. not via `mkOutOfStoreSymlink`):

```bash
home-manager switch --flake ~/Projects/home-manager#oryp6
```

Files managed with `mkOutOfStoreSymlink` (nvim plugins, opencode.json) are live immediately without re-running switch.
