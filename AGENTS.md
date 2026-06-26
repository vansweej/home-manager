# Home Manager Configuration — Agent Instructions

Nix flake-based home-manager configuration for multiple machines, managed from a
single repository.

---

## Repository Structure

```
flake.nix                          # mkHome helper and homeConfigurations outputs
machines/
  oryp6.nix                        # Metadata: system, username, homeDir, flags (x86_64-linux)
  m1.nix                           # Metadata: system, username, homeDir, flags (aarch64-darwin)
  m5.nix                           # Metadata: system, username, homeDir, flags (aarch64-darwin)
  parallels-ubuntu.nix             # Metadata: system, username, homeDir, flags (aarch64-linux)
modules/
  common.nix                       # Universal: programs, fonts, nvim symlinks, bootstrapNvim
  opencode.nix                     # OpenCode: auto-discovery, activation, session vars
  athenaeum.nix                    # Resolves store-built athenaeum-mcp binary; exposes dataDir option; registers MCP server + agent scoping
  sccache.nix                      # Local-only sccache compiler cache: RUSTC_WRAPPER + CARGO_INCREMENTAL=0
  linux.nix                        # Linux-only: nixGL wrapper (opt-in), .desktop file
  darwin.nix                       # macOS-only: placeholder for Darwin-specific config
  machines/
    oryp6.nix                      # oryp6-only: rootless Docker, systemd service
    m1.nix                         # M1-only: placeholder for M1-specific config
    m5.nix                         # M5-only: Ollama provider config, local agent override
    parallels-ubuntu.nix           # parallels-ubuntu-only: placeholder (test bed)
opencode/AGENTS.md                 # Machine-wide OpenCode agent instructions
opencode/skills/*/SKILL.md         # OpenCode skills deployed to ~/.config/opencode/skills/
opencode/agents/*.md               # OpenCode agents deployed to ~/.config/opencode/agents/
opencode/commands/*.md             # OpenCode commands deployed to ~/.config/opencode/commands/
opencode/tools/*.ts                # Tool implementations — auto-discovered; shell out to ai-coding monorepo at runtime
opencode/bin/*                     # Shell wrapper scripts deployed to ~/.local/bin/
nvim/                              # Neovim plugin files (symlinked via mkOutOfStoreSymlink)
flake.lock                         # Pinned dependency revisions (do not hand-edit)
.gitignore                         # Ignores: result, result-*, .direnv
```

There is no `devShell`, `checks`, `packages`, or `apps` output — this is a pure
home-manager configuration flake.

---

## Module Architecture

Each machine profile is composed from three layers:

```
common.nix          (all machines) — imports opencode.nix
    +
linux.nix           (x86_64-linux machines only)
  OR
darwin.nix          (aarch64-darwin machines only)
    +
modules/machines/<name>.nix   (that machine only)
```

`opencode.nix` is imported by `common.nix` and manages all OpenCode configuration:
agents, skills, commands, tools, session variables, and activation scripts.
It uses `builtins.readDir` to auto-discover files from the `opencode/` directory —
no manual `home.file` entries are needed when adding new agents, skills, or tools.

`sccache.nix` is also imported by `common.nix`. It installs `sccache` and sets
two session variables — `RUSTC_WRAPPER` (routes every `cargo build`, including
inside `nix develop` shells, through a local on-disk cache) and
`CARGO_INCREMENTAL=0` (so debug builds are cacheable, since sccache cannot cache
incremental compilation). Storage is local-disk only; no cloud backend is
configured. C/C++ launcher integration (`CMAKE_*_COMPILER_LAUNCHER`, autotools
`CC`/`CXX`) and future CUDA `nvcc` caching are left to per-project configuration.

Machine identity (`home.username`, `home.homeDirectory`, `home.stateVersion`) is
injected by the `mkHome` helper in `flake.nix` from the machine metadata file —
no module hardcodes these values.

### Adding a new machine

1. Create `machines/<name>.nix` with the plain metadata attrset:
   ```nix
   {
     system = "aarch64-darwin";   # or "x86_64-linux"
     username = "myuser";
     homeDirectory = "/Users/myuser";
     stateVersion = "25.11";
     cudaSupport = false;
   }
   ```
2. Create `modules/machines/<name>.nix` with the machine-specific home-manager module.
3. Add to `flake.nix`:
   ```nix
   homeConfigurations."<name>" = mkHome ./machines/<name>.nix ./modules/machines/<name>.nix;
   ```

---

## Commands

### Apply the configuration

```bash
# oryp6 (Linux)
home-manager switch --flake .#oryp6

# M1 MacBook
home-manager switch --flake .#M1
```

### Dry-run / build without activating

```bash
nix build .#homeConfigurations.oryp6.activationPackage
nix build .#homeConfigurations.M1.activationPackage
```

### Check the flake for evaluation errors

```bash
nix flake check
```

### Update all inputs

```bash
nix flake update
```

### Update a single input

```bash
nix flake update nixpkgs
```

### Format Nix files

```bash
nix fmt
```

> Note: `nix fmt` requires a `formatter` output in the flake. If none is defined,
> use `nixpkgs-fmt` or `alejandra` manually.

---

## No Tests

There are no unit tests in this repository. Validation is done by:

1. `nix flake check` — evaluates the flake without activating
2. `nix build .#homeConfigurations.oryp6.activationPackage` — full build (regression gate)
3. `home-manager switch --flake .#oryp6` — apply and verify at runtime

Always run step 1 and 2 before committing structural changes.

---

## Workflow

- Always work on a **feature branch** created from `main`, unless told otherwise.
- Commit messages must follow **Conventional Commits** format:
  - `feat: add bat configuration`
  - `fix: correct ghostty font name`
  - `chore: update flake inputs`
  - `refactor: extract ghostty wrapper into separate file`
- Never commit `flake.lock` changes alongside functional changes — keep them separate.
- The `result` and `result-*` symlinks produced by `nix build` are gitignored; never commit them.
- All new `.nix` files must be `git add`-ed before `nix build` — Nix flakes only
  see git-tracked files.

---

## Nix Code Style

### Indentation and formatting

- Use **2-space indentation** throughout all `.nix` files.
- Attribute sets: one attribute per line when the set has more than one entry.
- Closing `}` or `];` aligns with the opening statement, not indented further.

### Let bindings

- Use `let ... in` at the top of a module for local values (e.g. custom package
  wrappers). Keep the `let` block minimal — only values used in the module body.

```nix
let
  my-wrapper = pkgs.writeShellScriptBin "my-wrapper" ''
    exec ${pkgs.some-tool}/bin/some-tool "$@"
  '';
in
{
  home.packages = [ my-wrapper ];
}
```

### Package lists

- Use `with pkgs;` for `home.packages` lists to avoid repetitive `pkgs.` prefixes.
- One package per line; group related packages with a blank line and a comment.

```nix
home.packages = with pkgs; [
  # Fonts
  nerd-fonts.fira-code

  # Terminal
  ghostty-nixgl
];
```

### String interpolation

- Use `${ }` for Nix string interpolation (standard).
- Multi-line strings use `''...''` (indented string literals).

### Comments

- Use `#` for inline and block comments.
- Preserve the standard home-manager template comment blocks as documentation
  scaffolding — they explain options for future maintainers.
- Commented-out example snippets are acceptable; they document available patterns.

### Paths

- Use relative paths for local file references within the same module directory.
- Use `../` to reference sibling directories (e.g. `../opencode/AGENTS.md` from
  inside `modules/`).
- Never use absolute paths inside any module.

### Programs and services

- Configure programs via `programs.<name>` attributes, not by writing dotfiles
  manually unless `home.file` is necessary (e.g. for non-program-managed config).
- Configure background services via `services.<name>` (Linux) or `launchd` (Darwin).
- Never put `systemd` config in `common.nix` or `darwin.nix` — it only belongs in
  Linux machine modules.

---

## Key Packages and Services

| Name | Type | Module | Notes |
|---|---|---|---|
| `ghostty-nixgl` | Custom wrapper | `modules/linux.nix` | Runs `ghostty` via `nixGLIntel`; Linux only |
| `nixgl.nixGLIntel` | Package | `modules/linux.nix` | OpenGL wrapper; Linux only |
| `ghostty` | Program (`programs.ghostty`) | `modules/common.nix` | Font: FiraCode Nerd Font; Theme: Night Owl |
| `nerd-fonts.fira-code` | Package | `modules/common.nix` | FiraCode Nerd Font |
| `docker` | Package | `modules/machines/oryp6.nix` | Rootless Docker; oryp6 only |
| `neovim` | Program (`programs.neovim`) | `modules/common.nix` | Default editor; aliased as `vim` and `vi` |
| `bat` | Program (`programs.bat`) | `modules/common.nix` | Enabled with defaults |
| `git` | Program (`programs.git`) | `modules/common.nix` | User: Jan Van Sweevelt / vansweej@gmail.com |
| `systemd docker service` | `systemd.user.services` | `modules/machines/oryp6.nix` | Rootless Docker daemon; oryp6 only |
| `sccache` | Package + env (`RUSTC_WRAPPER`, `CARGO_INCREMENTAL`) | `modules/sccache.nix` | Local-only Rust/C++ compiler cache; all machines |
| `watchexec` | Package | `modules/athenaeum.nix` | Cross-platform file watcher; drives the corpus reingest; oryp6 + M1 + M5 |
| `athenaeum-watch` | `systemd.user.services` (Linux) / `launchd.agents` (Darwin) | `modules/machines/{oryp6,m1,m5}.nix` | Watches `~/Documents/corpus`; runs `athenaeum-ingest` on change |
| `cerebrum` | MCP server (via `cerebrum-wrapped`) | `modules/cerebrum.nix` | Two-tier agent memory (Synapse + Cortex); all machines; all agents; MockEmbedder (offline) |

---

## Flake Inputs

| Input | Source | Notes |
|---|---|---|
| `nixpkgs` | `github:nixos/nixpkgs/nixos-unstable` | `allowUnfree = true`; `cudaSupport` per machine |
| `home-manager` | `github:nix-community/home-manager` | Follows the same `nixpkgs` |
| `nixgl` | `github:guibou/nixGL` | Overlay applied on Linux only; never on Darwin |
| `ai-coding` | `github:vansweej/ai-coding` | Two-phase Nix derivation; `node_modules` baked in; pinned in `flake.lock` |
| `athenaeum` | `github:vansweej/athenaeum-mcp` | Built by Nix into a store binary (mirrors `ai-coding`); `inputs.nixpkgs.follows = "nixpkgs"`; updated via `nix flake update athenaeum` |
| `cerebrum` | `github:vansweej/cerebrum-mcp` | Two-tier memory MCP server; `inputs.nixpkgs.follows = "nixpkgs"`; updated via `nix flake update cerebrum` |

The `nixgl.overlay` is conditionally applied in `mkHome` based on `isDarwin`,
making `pkgs.nixgl.*` available only on Linux builds.

The `ai-coding` input is updated with `nix flake update ai-coding`. Always commit
`flake.lock` after updating and run `home-manager switch` to apply.

The `athenaeum` input is updated with `nix flake update athenaeum`. The store-built
binary is launched with `cwd` set to `~/.local/share/athenaeum` (created by per-machine
`home.activation` scripts), so the server's relative `db_path` (`./data/athenaeum`)
resolves to a writable location outside the Nix store. Existing ingested data is not
migrated on switch — re-ingest after deploying.

The `cerebrum` input is updated with `nix flake update cerebrum`. The store-built
wrapped binary creates `~/.local/share/cerebrum` on first run and cd's into it, so
no activation script or cwd pinning is needed. Data persists as a LanceDB table at
`~/.local/share/cerebrum/data/cerebrum/memories.lance`. The shipped binary uses
`MockEmbedder` (hash-based, offline) — semantic search via Ollama is a future
upgrade. Tools (`cerebrum_remember`, `cerebrum_recall`, `cerebrum_memorize`,
`cerebrum_forget`, `cerebrum_end_session`, `cerebrum_recall_by_scope`) are enabled
for all agents with no per-agent gating. Per-agent memory isolation via the
`recall_by_scope` tool's `agent:<id>` scope is supported by the server but not yet
configured — all memories currently land in the `global` scope.

### Running bulk ingest

The `athenaeum-ingest` CLI is on `$PATH` (only this binary; the MCP server is not).
Both the CLI and the server resolve a relative `db_path` (`./data/athenaeum`)
against the current working directory, so the CLI must be run from the data dir to
write into the same database the MCP server reads:

```bash
cd ~/.local/share/athenaeum
athenaeum-ingest <directory> --recursive --verbose
```

`<directory>` is a folder of PDF/EPUB files. Omit `--recursive` to ingest only the
top level. The server picks up newly ingested content on its next `athenaeum_search`
(no restart needed). Existing data is not migrated on `home-manager switch` — re-run
this command to repopulate after a fresh deploy. Requires Ollama running at
`localhost:11434` with `nomic-embed-text`.

### Corpus directory watcher

A long-running watcher reingests the corpus automatically when files change.
`watchexec` is the only resident process; on each debounced change it invokes the
short-lived `athenaeum-ingest` CLI. Athenaeum itself is never a daemon.

- **Watched directory:** `~/Documents/corpus` (option `programs.athenaeum.watchDir`,
  default in `modules/athenaeum.nix`). Deliberately non-hidden so it is reachable
  from file-manager tools and the PDFs/EPUBs can be browsed directly. Separate from
  the LanceDB store under `~/.local/share/athenaeum/data`.
- **Trigger semantics:** any change triggers a *full recursive* reingest of the
  whole directory. Safe because `athenaeum-ingest` upserts per file (delete-then-add
  keyed on the canonical absolute path), so re-ingesting does not duplicate rows.
  Deleting a file does **not** remove its embeddings — there is no prune path yet.
- **Relative db_path:** the CLI's `db_path` is the relative `./data/athenaeum`, so
  it resolves against the working directory. The watcher pins cwd to
  `~/.local/share/athenaeum` in **two** ways — `watchexec --workdir` (the ingest
  subprocess) and the unit's working directory (`WorkingDirectory=` on Linux,
  `WorkingDirectory` key on macOS) — so it always writes the same store the MCP
  server reads. It must **not** be run from the corpus dir, or a stray DB would be
  created there.
- **No startup reingest:** runs with `--postpone`, so it does **not** reingest at
  boot or on `home-manager switch` — only on a genuine post-startup change. To
  ingest files added while the watcher was stopped, run the CLI manually:
  ```bash
  cd ~/.local/share/athenaeum
  athenaeum-ingest ~/Documents/corpus --recursive --verbose
  ```
- **Per-OS unit:** `systemd.user.services.athenaeum-watch` on Linux (logs to the
  journal: `journalctl --user -u athenaeum-watch`); `launchd.agents.athenaeum-watch`
  on macOS (logs to `~/.local/share/athenaeum/watch.log` and `watch.err.log`).
- **Requires** Ollama at `localhost:11434` with `nomic-embed-text`, same as manual
  ingest.
- **Runbook:** operational health checks, log locations, the smoke test, and
  troubleshooting are in [`docs/athenaeum-watcher.md`](docs/athenaeum-watcher.md).

---

## OpenCode Skills

The `opencode/` directory mirrors the XDG deployment target exactly:

| Repo path | Deployed to |
|---|---|
| `opencode/AGENTS.md` | `~/.config/opencode/AGENTS.md` |
| `opencode/skills/<name>/SKILL.md` | `~/.config/opencode/skills/<name>/SKILL.md` |
| `opencode/agents/<name>.md` | `~/.config/opencode/agents/<name>.md` |
| `opencode/commands/<name>.md` | `~/.config/opencode/commands/<name>.md` |
| `opencode/tools/<name>.ts` | `~/.config/opencode/tools/<name>.ts` → symlink to `~/Projects/home-manager/opencode/tools/` |
| `opencode/bin/<name>` | `~/.local/bin/<name>` (executable, nix-store copy) |

All four categories are **auto-discovered** by `modules/opencode.nix` using
`builtins.readDir`. No manual `home.file` entries are needed.

### Adding a new agent, skill, or command

Drop the file in the correct directory, `git add` it, and run `home-manager switch`.

```bash
# New agent
cp my-agent.md opencode/agents/my-agent.md
git add opencode/agents/my-agent.md

# New skill
mkdir -p opencode/skills/my-skill
cp SKILL.md opencode/skills/my-skill/SKILL.md
git add opencode/skills/my-skill/SKILL.md

# New command
cp my-command.md opencode/commands/my-command.md
git add opencode/commands/my-command.md
```

### Adding a new OpenCode tool

Tools are full TypeScript implementations that live in `opencode/tools/` in this
repo. They are deployed as live symlinks to `~/Projects/home-manager/opencode/tools/`
via `mkOutOfStoreSymlink`, so bun can resolve `node_modules` relative to the file
at runtime. At runtime, tools delegate to the ai-coding monorepo via subprocess
(`bun run --cwd $AI_CODING_MONOREPO <script>`).

**Developer workflow (Nix):**
1. Implement the tool in `opencode/tools/<name>.ts` in this repo
2. `git add opencode/tools/<name>.ts` and `home-manager switch`
3. The tool is live immediately — `mkOutOfStoreSymlink` means edits to the file
   are picked up without re-running switch

**When the tool shells out to ai-coding:**
- Edit the underlying script in the ai-coding repo
- Push to a branch, `nix flake update ai-coding` in home-manager, `home-manager switch`
- Or point `AI_CODING_MONOREPO` at a local clone temporarily for fast iteration

At runtime, `~/.config/opencode/tools/<name>.ts` is a live symlink to
`~/Projects/home-manager/opencode/tools/<name>.ts`, so bun resolves
`node_modules` from `~/.config/opencode/` (where `@opencode-ai/plugin` is installed
by the `installAiCodingDeps` activation script).

---

### Adding a new CLI wrapper

Shell wrapper scripts in `opencode/bin/` are deployed to `~/.local/bin/` as
nix-store copies with the executable bit set. Auto-discovered by
`builtins.readDir` — no manual `home.file` entries needed. Convention: files
in `bin/` have no extension and are plain bash scripts.

1. Create the script in `opencode/bin/<name>` (no file extension)
2. `git add opencode/bin/<name>` and `home-manager switch`

Scripts use `$AI_CODING_MONOREPO` (set globally by Home Manager) to locate the
monorepo and delegate to `bun run --cwd "$monorepo" <script-name>`.

---

## Common Mistakes to Avoid

- Do **not** edit `flake.lock` by hand — use `nix flake update`.
- Do **not** set `home.stateVersion` in any module — it is set by `mkHome` from
  the machine metadata file.
- Do **not** set `home.username` or `home.homeDirectory` in any module — same reason.
- Do **not** use `pkgs.ghostty` directly in `home.packages` on Linux — use the
  `ghostty-nixgl` wrapper from `linux.nix`, or hardware acceleration will fail.
- Do **not** add `result` or `result-*` to git; they are gitignored build outputs.
- Do **not** put `systemd` configuration in `common.nix` or `darwin.nix` — the
  `systemd` module does not exist on Darwin and will cause evaluation failure.
- Do **not** forget to `git add` new `.nix` files before running `nix build` —
  Nix flakes only evaluate git-tracked files.
- Avoid `home.file` for programs that have a `programs.<name>` home-manager module —
  prefer the structured module so options are type-checked.
