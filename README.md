# home-manager

Personal [Home Manager](https://github.com/nix-community/home-manager) configuration
for multiple machines, managed from a single repository.

| Profile | Machine | OS |
|---|---|---|
| `oryp6` | Oryx Pro 6 | x86_64-linux |
| `M1` | MacBook (work, retiring) | aarch64-darwin |
| `M5` | MacBook (work) | aarch64-darwin |
| `parallels` | Parallels Linux VM | x86_64-linux |
| `parallels-ubuntu` | Parallels Ubuntu VM | aarch64-linux |

## What this manages

- **Packages** — ghostty, neovim, bat, starship, bun, htop, tree, fonts
- **Shell** — bash + starship prompt
- **Neovim** — LazyVim bootstrapped on first run; custom plugin files symlinked live
- **OpenCode** — agent profiles, skill definitions, pipeline commands and tool
- **Docker** — rootless daemon via systemd user service (oryp6 only)
- **Fonts** — FiraCode Nerd Font
- **ai-coding** — runtime monorepo fetched from GitHub and built into the Nix store; no manual clone needed
- **Athenaeum corpus watcher** — watches `~/Documents/corpus` and reingests PDFs/EPUBs on change (systemd user service on Linux, launchd agent on macOS)

## Quick start

### Prerequisites

- Nix installed with flakes enabled
- Home Manager installed (standalone)

### oryp6 (Linux)

```bash
git clone git@github.com:vansweej/home-manager.git ~/Projects/home-manager
home-manager switch --flake ~/Projects/home-manager#oryp6
```

### M1 MacBook (macOS)

```bash
git clone git@github.com:vansweej/home-manager.git ~/Projects/home-manager
home-manager switch --flake ~/Projects/home-manager#M1
```

### M5 MacBook (macOS)

```bash
git clone git@github.com:vansweej/home-manager.git ~/Projects/home-manager
home-manager switch --flake ~/Projects/home-manager#M5
```

On first activation, the following happen automatically:

1. `~/.config/nvim` is bootstrapped from the LazyVim starter
2. All packages, dotfiles, and symlinks are installed

Open Neovim after activation — LazyVim bootstraps plugins automatically:

```bash
nvim
```

## Applying changes

After editing any Nix-managed file:

```bash
# Linux
home-manager switch --flake ~/Projects/home-manager#oryp6

# macOS
home-manager switch --flake ~/Projects/home-manager#M5
```

Files managed with `mkOutOfStoreSymlink` (nvim plugins, `opencode.json`) update
immediately without re-running switch.

## Validate without activating

```bash
nix flake check
nix build .#homeConfigurations.oryp6.activationPackage
nix build .#homeConfigurations.M5.activationPackage
```

## Setting up OpenCode without Nix

If you don't use Nix or home-manager, colleague-facing distributable
artifacts (agents, skills) are produced by
[`agora`](https://github.com/vansweej/agora), not by this repo — install
with [`apm`](https://github.com/microsoft/apm) (Agent Package Manager):

```bash
apm install vansweej/agora -t opencode -g                # OpenCode
apm install vansweej/agora/clients/claude -t claude -g   # Claude Code
```

See `agora`'s README for the full install/compile sequence and what each
package contains. The previous `generate-tarball.sh` monolith has been
removed — the apm packages in `agora` replace it.

---

## Further reading

- [Architecture](docs/architecture.md) — module layers, flake design, `mkHome` helper
- [Adding a machine](docs/adding-a-machine.md) — step-by-step guide
- [What each module manages](docs/modules.md) — reference for `common`, `linux`, `darwin`, and machine modules
- [Athenaeum watcher runbook](docs/athenaeum-watcher.md) — health checks, logs, smoke test, and troubleshooting for the corpus watcher
- [Agora integration](docs/agora-integration.md) — how `opencode.nix` /
  `claude.nix` consume agora's apm-native content, and how that relates to
  colleagues installing the same content via `apm`
