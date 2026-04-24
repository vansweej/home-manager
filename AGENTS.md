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
modules/
  common.nix                       # Universal: programs, fonts, dotfiles, activation scripts
  linux.nix                        # Linux-only: nixGL wrapper, .desktop file
  darwin.nix                       # macOS-only: placeholder for Darwin-specific config
  machines/
    oryp6.nix                      # oryp6-only: rootless Docker, systemd service
    m1.nix                         # M1-only: placeholder for M1-specific config
opencode/AGENTS.md                 # Machine-wide OpenCode agent instructions
opencode/skill/*/SKILL.md          # OpenCode skills deployed to ~/.config/opencode/skill/
opencode/agents/*.md               # OpenCode agents deployed to ~/.config/opencode/agents/
opencode/commands/*.md             # OpenCode commands deployed to ~/.config/opencode/commands/
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
common.nix          (all machines)
    +
linux.nix           (x86_64-linux machines only)
  OR
darwin.nix          (aarch64-darwin machines only)
    +
modules/machines/<name>.nix   (that machine only)
```

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

---

## Flake Inputs

| Input | Source | Notes |
|---|---|---|
| `nixpkgs` | `github:nixos/nixpkgs/nixos-unstable` | `allowUnfree = true`; `cudaSupport` per machine |
| `home-manager` | `github:nix-community/home-manager` | Follows the same `nixpkgs` |
| `nixgl` | `github:guibou/nixGL` | Overlay applied on Linux only; never on Darwin |

The `nixgl.overlay` is conditionally applied in `mkHome` based on `isDarwin`,
making `pkgs.nixgl.*` available only on Linux builds.

---

## OpenCode Skills

The `opencode/` directory mirrors the XDG deployment target exactly:

| Repo path | Deployed to |
|---|---|
| `opencode/AGENTS.md` | `~/.config/opencode/AGENTS.md` |
| `opencode/skill/<name>/SKILL.md` | `~/.config/opencode/skill/<name>/SKILL.md` |
| `opencode/agents/<name>.md` | `~/.config/opencode/agents/<name>.md` |
| `opencode/commands/<name>.md` | `~/.config/opencode/commands/<name>.md` |

When adding a new skill, add both the file under `opencode/skill/<name>/SKILL.md`
and a corresponding `home.file` entry in `modules/common.nix`.

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
