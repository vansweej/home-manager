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

If you don't use Nix or home-manager, you can get the full global OpenCode CLI
setup (agents, skills, commands, pipeline tool) by generating a self-contained
tarball on your machine and extracting it into `~/.config/opencode/`.

### Prerequisites

- [OpenCode CLI](https://opencode.ai) installed
- [Bun](https://bun.sh) runtime installed
  - macOS: `brew install bun`
  - Linux / WSL: `curl -fsSL https://bun.sh/install | bash`
- Git

### Steps

**1. Clone this repo**

```bash
git clone https://github.com/vansweej/home-manager.git ~/Projects/home-manager
```

**2. Generate the tarball**

```bash
cd ~/Projects/home-manager
./generate-tarball.sh
```

The script automatically packs agents, skills, commands, tools, and bin wrappers
into `opencode-setup-YYYY-MM-DD.tar.gz`. The ai-coding monorepo runtime is
fetched separately — see step 5 below.

**3. Inspect before applying (recommended)**

```bash
tar tf opencode-setup-$(date +%Y-%m-%d).tar.gz | grep -v node_modules
```

**4. Back up and extract**

```bash
cp -r ~/.config/opencode ~/.config/opencode.bak   # optional backup
tar xzf opencode-setup-$(date +%Y-%m-%d).tar.gz -C ~/
```

This places OpenCode config in `~/.config/opencode/` and CLI wrapper scripts
(`codebase-retrieval`, `index-codebase`) in `~/.local/bin/`.

**5. Configure your shell profile**

Add to `~/.bashrc`, `~/.zshrc`, or equivalent:

```bash
export AI_CODING_MONOREPO="$HOME/Projects/ai-coding"   # path to the ai-coding clone
export PATH="$HOME/.opencode/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
```

> **Nix users:** `AI_CODING_MONOREPO` is set automatically by Home Manager to the
> Nix store path of the ai-coding package. No manual export needed.

Then reload: `source ~/.bashrc` (or `~/.zshrc`).

**6. Restart OpenCode** to pick up the new configuration.

### Updating

Pull both repos, regenerate, and do a clean re-extract to avoid stale files:

```bash
cd ~/Projects/home-manager && git pull
./generate-tarball.sh --clean
rm -rf ~/.config/opencode
rm -f ~/.local/bin/codebase-retrieval ~/.local/bin/index-codebase
tar xzf ~/Projects/home-manager/opencode-setup-$(date +%Y-%m-%d).tar.gz -C ~/
```

See `README-install.md` inside the tarball for full details.

---

## Further reading

- [Architecture](docs/architecture.md) — module layers, flake design, `mkHome` helper
- [Adding a machine](docs/adding-a-machine.md) — step-by-step guide
- [What each module manages](docs/modules.md) — reference for `common`, `linux`, `darwin`, and machine modules
- [Athenaeum watcher runbook](docs/athenaeum-watcher.md) — health checks, logs, smoke test, and troubleshooting for the corpus watcher
