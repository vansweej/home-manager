# Home Manager Configuration — Agent Instructions

Nix flake-based home-manager configuration for user `vansweej` on `x86_64-linux`.

---

## Repository Structure

```
flake.nix                        # Flake inputs and homeConfigurations output
home.nix                         # All packages, programs, dotfiles, services
opencode/AGENTS.md               # Machine-wide OpenCode agent instructions
opencode/skill/*/SKILL.md        # OpenCode skills deployed to ~/.config/opencode/skill/
flake.lock                       # Pinned dependency revisions (do not hand-edit)
.gitignore                       # Ignores: result, result-*, .direnv
```

There is no `devShell`, `checks`, `packages`, or `apps` output — this is a pure
home-manager configuration flake.

---

## Commands

### Apply the configuration

```bash
home-manager switch --flake .#oryp6
```

### Dry-run / build without activating

```bash
nix build .#homeConfigurations.oryp6.activationPackage
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
2. `nix build .#homeConfigurations.oryp6.activationPackage` — full build
3. `home-manager switch --flake .#oryp6` — apply and verify at runtime

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

- Always use relative paths for local file references: `./opencode/AGENTS.md`.
- Never use absolute paths inside `home.nix`.

### Programs and services

- Configure programs via `programs.<name>` attributes, not by writing dotfiles
  manually unless `home.file` is necessary (e.g. for non-program-managed config).
- Configure background services via `services.<name>`.

---

## Key Packages and Services

| Name | Type | Notes |
|---|---|---|
| `ghostty-nixgl` | Custom wrapper | Runs `ghostty` via `nixGLIntel` for OpenGL on non-NixOS |
| `nixgl.nixGLIntel` | Package | OpenGL wrapper; required for GPU apps outside NixOS |
| `ghostty` | Program (`programs.ghostty`) | Font: FiraCode Nerd Font; Theme: Night Owl |
| `nerd-fonts.fira-code` | Package | FiraCode Nerd Font |
| `opencode` | Package | AI coding agent |
| `ollama` | Service (`services.ollama`) | Local LLM; CUDA acceleration; `127.0.0.1:11434` |
| `neovim` | Program (`programs.neovim`) | Default editor; aliased as `vim` and `vi` |
| `bat` | Program (`programs.bat`) | Enabled with defaults |
| `git` | Program (`programs.git`) | User: Jan Van Sweevelt / vansweej@gmail.com |

---

## Flake Inputs

| Input | Source | Notes |
|---|---|---|
| `nixpkgs` | `github:nixos/nixpkgs/nixos-unstable` | `allowUnfree = true`, `cudaSupport = true` |
| `home-manager` | `github:nix-community/home-manager` | Follows the same `nixpkgs` |
| `nixgl` | `github:guibou/nixGL` | Overlay applied to `pkgs` |

The `nixgl.overlay` is applied when instantiating `pkgs`, making `pkgs.nixgl.*`
available in `home.nix`.

---

## OpenCode Skills

The `opencode/` directory mirrors the XDG deployment target exactly:

| Repo path | Deployed to |
|---|---|
| `opencode/AGENTS.md` | `~/.config/opencode/AGENTS.md` |
| `opencode/skill/<name>/SKILL.md` | `~/.config/opencode/skill/<name>/SKILL.md` |

When adding a new skill, add both the file under `opencode/skill/<name>/SKILL.md`
and a corresponding `home.file` entry in `home.nix`.

---

## Common Mistakes to Avoid

- Do **not** edit `flake.lock` by hand — use `nix flake update`.
- Do **not** set `home.stateVersion` to the current date; it tracks the version at
  first setup and should remain `"25.11"` unless intentionally migrating.
- Do **not** use `pkgs.ghostty` directly in `home.packages` — use `ghostty-nixgl`
  wrapper instead, or hardware acceleration will fail on this non-NixOS system.
- Do **not** add `result` or `result-*` to git; they are gitignored build outputs.
- Avoid `home.file` for programs that have a `programs.<name>` home-manager module —
  prefer the structured module so options are type-checked.
