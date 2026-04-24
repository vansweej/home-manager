# Plan: Multi-Machine Home-Manager Support

## Goal

Restructure the home-manager flake so it supports multiple machines (starting with
`oryp6` on Linux and `M1` on macOS) via composable Nix modules, while keeping
everything in a single repository. The architecture must scale to 4+ machines that
drift independently.

---

## Target Directory Structure

```
flake.nix                          # mkHome helper, all homeConfigurations
machines/
  oryp6.nix                        # Metadata: system, username, homeDir, flags
  m1.nix                           # Metadata: system, username, homeDir, flags
modules/
  common.nix                       # Universal: programs, fonts, dotfiles, activation
  linux.nix                        # Linux-only: nixGL, .desktop files
  darwin.nix                       # macOS-only: (minimal initially)
  machines/
    oryp6.nix                      # oryp6-only: Docker, systemd, CUDA packages
    m1.nix                         # M1-only: (minimal initially)
opencode/                          # (unchanged)
nvim/                              # (unchanged)
AGENTS.md                          # Updated to reflect new structure
```

The old `home.nix` is **deleted** after being decomposed into these files.

---

## Line-by-Line Classification of `home.nix`

Every line of the current `home.nix` is accounted for and assigned to a target module.

| Lines | Content | Target |
|---|---|---|
| 3–5 | `ghostty-nixgl` let binding (`nixGLIntel` wrapper) | `modules/linux.nix` |
| 10 | `home.username = "vansweej"` | `flake.nix` inline identity module (from metadata) |
| 11 | `home.homeDirectory = "/home/vansweej"` | `flake.nix` inline identity module (from metadata) |
| 20 | `home.stateVersion = "25.11"` | `flake.nix` inline identity module (from metadata) |
| 22 | `fonts.fontconfig.enable = true` | `modules/common.nix` |
| 24 | `xdg.enable = true` | `modules/common.nix` |
| 29 | `nerd-fonts.fira-code` | `modules/common.nix` |
| 31 | `nixgl.nixGLIntel` | `modules/linux.nix` |
| 33 | `ghostty-nixgl` | `modules/linux.nix` |
| 35 | `htop` | `modules/common.nix` |
| 37 | `bun` | `modules/common.nix` |
| 39 | `tree` | `modules/common.nix` |
| 41–44 | `docker`, `slirp4netns`, `rootlesskit` | `modules/machines/oryp6.nix` |
| 68–80 | `.desktop` file for ghostty-nixgl | `modules/linux.nix` |
| 82–92 | opencode skill `home.file` entries | `modules/common.nix` |
| 102–117 | opencode agent `home.file` entries | `modules/common.nix` |
| 121–123 | opencode command `home.file` entries | `modules/common.nix` |
| 128–130 | `pipeline.ts` mkOutOfStoreSymlink | `modules/common.nix` |
| 137–145 | nvim plugin mkOutOfStoreSymlinks | `modules/common.nix` |
| 149–151 | `opencode.json` mkOutOfStoreSymlink | `modules/common.nix` |
| 169 | `DOCKER_HOST` sessionVariable | `modules/machines/oryp6.nix` |
| 170 | `AI_CODING_MONOREPO` sessionVariable | `modules/common.nix` |
| 174–176 | `home.sessionPath` (opencode bin) | `modules/common.nix` |
| 181–189 | `bootstrapNvim` activation script | `modules/common.nix` |
| 192–198 | `cloneAiCoding` activation script | `modules/common.nix` **(with ordering fix — see Risks)** |
| 200–218 | `systemd.user.services.docker` | `modules/machines/oryp6.nix` |
| 220–222 | `programs.bat` | `modules/common.nix` |
| 224–230 | `programs.bash` | `modules/common.nix` |
| 232–235 | `programs.starship` | `modules/common.nix` |
| 237–243 | `programs.ghostty` | `modules/common.nix` |
| 245–253 | `programs.git` | `modules/common.nix` |
| 255–260 | `programs.neovim` | `modules/common.nix` |
| 263 | `programs.home-manager.enable` | `modules/common.nix` |

---

## Step-by-Step Implementation

### Step 0 — Create feature branch

```bash
git checkout -b feat/multi-machine
```

---

### Step 1 — Create directory structure

Create the following empty directories:

```
machines/
modules/
modules/machines/
```

---

### Step 2 — Create machine metadata files

These are **plain Nix attrsets**, NOT home-manager modules. They are imported
directly by `flake.nix` before `pkgs` is instantiated.

**`machines/oryp6.nix`**:
```nix
{
  system = "x86_64-linux";
  username = "vansweej";
  homeDirectory = "/home/vansweej";
  stateVersion = "25.11";
  cudaSupport = true;
}
```

**`machines/m1.nix`**:
```nix
{
  system = "aarch64-darwin";
  username = "janvansweevelt";
  homeDirectory = "/Users/janvansweevelt";
  stateVersion = "25.11";
  cudaSupport = false;
}
```

---

### Step 3 — Create `modules/common.nix`

The largest file. Receives `{ pkgs, lib, config, inputs, ... }` and contains
everything that is universal across all machines.

Contents (in order):

- `fonts.fontconfig.enable = true`
- `xdg.enable = true`
- `home.packages` with: `nerd-fonts.fira-code`, `htop`, `bun`, `tree`
- All `home.file` entries for opencode skills, agents, commands, pipeline tool,
  nvim plugins, opencode.json (lines 82–151 of current `home.nix`, minus the
  `.desktop` file which goes to `linux.nix`)
- `home.sessionVariables.AI_CODING_MONOREPO`
- `home.sessionPath` with `$HOME/.opencode/bin`
- `home.activation.bootstrapNvim` — unchanged (`entryBefore [ "writeBoundary" ]`)
- `home.activation.cloneAiCoding` — **ordering fix applied** (see Risks section)
- `programs.bat`, `programs.bash`, `programs.starship`, `programs.ghostty`,
  `programs.git`, `programs.neovim`, `programs.home-manager`

---

### Step 4 — Create `modules/linux.nix`

Contains a `let` block defining `ghostty-nixgl`, then:

- `home.packages` with: `nixgl.nixGLIntel`, `ghostty-nixgl`
- `home.file.".local/share/applications/ghostty-nixgl.desktop"` — the `.desktop`
  file (references `ghostty-nixgl` from the let block)

---

### Step 5 — Create `modules/darwin.nix`

Minimal placeholder for future macOS-specific config:

```nix
{ pkgs, lib, config, ... }:
{
  # macOS-specific configuration.
  # Add Darwin-only packages, settings, or launchd services here.
}
```

This file exists so the module composition in `flake.nix` has a Darwin counterpart
to `linux.nix`. It will grow when macOS-specific needs emerge (e.g., `launchd`
services, macOS defaults).

---

### Step 6 — Create `modules/machines/oryp6.nix`

Contains everything specific to the oryp6 Linux machine:

- `home.packages` with: `docker`, `slirp4netns`, `rootlesskit`
- `home.sessionVariables.DOCKER_HOST = "unix:///run/user/1000/docker.sock"`
- The entire `systemd.user.services.docker` block

---

### Step 7 — Create `modules/machines/m1.nix`

Minimal placeholder:

```nix
{ pkgs, lib, config, ... }:
{
  # M1 MacBook-specific configuration.
  # Add M1-only packages, settings, or launchd services here.
}
```

---

### Step 8 — Refactor `flake.nix`

Replace the single hardcoded `system`/`pkgs`/`homeConfigurations."oryp6"` with a
`mkHome` helper function.

```nix
{
  description = "Home Manager configuration of vansweej";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl.url = "github:guibou/nixGL";
  };

  outputs =
    { self, nixpkgs, home-manager, nixgl, ... }@inputs:
    let
      mkHome = machineMetaPath: machineModulePath:
        let
          meta = import machineMetaPath;
          isDarwin = builtins.match ".*-darwin" meta.system != null;

          pkgs = import nixpkgs {
            system = meta.system;
            config.allowUnfree = true;
            config.cudaSupport = meta.cudaSupport;
            overlays = if isDarwin then [] else [ nixgl.overlay ];
          };
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          extraSpecialArgs = {
            inherit inputs meta;
          };

          modules = [
            # Per-machine identity (derived from metadata)
            {
              home.username = meta.username;
              home.homeDirectory = meta.homeDirectory;
              home.stateVersion = meta.stateVersion;
            }

            # Universal configuration
            ./modules/common.nix
          ]
          # Platform-specific module
          ++ (if isDarwin
              then [ ./modules/darwin.nix ]
              else [ ./modules/linux.nix ])
          # Machine-specific module
          ++ [ machineModulePath ];
        };

    in
    {
      homeConfigurations."oryp6" = mkHome ./machines/oryp6.nix ./modules/machines/oryp6.nix;
      homeConfigurations."M1"    = mkHome ./machines/m1.nix    ./modules/machines/m1.nix;
    };
}
```

**Key design points:**
- `isDarwin` is derived from the system string — works for any `*-darwin` system
- `nixgl.overlay` only applied on Linux — avoids eval errors on Darwin
- `cudaSupport` comes from machine metadata — only `true` for oryp6
- `meta` passed via `extraSpecialArgs` so any module can read machine metadata
- The inline identity module sets `home.username`, `home.homeDirectory`,
  `home.stateVersion` — no machine module needs to repeat these

---

### Step 9 — Delete `home.nix`

Once all content has been moved and verified, remove the old monolithic file.

---

### Step 10 — Update `AGENTS.md`

Update the repository structure section to reflect the new layout. Update the
commands section to include the `M1` profile. Update the Key Packages table.

---

### Step 11 — Validate

Run in order, fixing any errors before proceeding to the next:

```bash
# 1. Evaluate the flake — catches Nix syntax and type errors
nix flake check

# 2. Build oryp6 — must produce identical result to pre-refactor
nix build .#homeConfigurations.oryp6.activationPackage

# 3. Build M1 — cross-compilation check (will build aarch64-darwin derivations)
nix build .#homeConfigurations.M1.activationPackage
```

The oryp6 build is the regression gate — if it succeeds with the same packages and
files as before, the refactor is safe.

---

## Risks and Mitigations

### Risk 1 — Activation ordering bug (HIGH, pre-existing)

**Problem:** `mkOutOfStoreSymlink` entries are created during `writeBoundary`, but
`cloneAiCoding` currently runs *after* `writeBoundary` (`entryAfter`). On a fresh
machine, symlinks into `~/Projects/ai-coding/` are created before the repo is
cloned, leaving dangling symlinks on first activation.

**Fix:** Change `cloneAiCoding` from `entryAfter [ "writeBoundary" ]` to
`entryBefore [ "writeBoundary" ]`, and add a `mkdir -p "$HOME/Projects"` guard:

```nix
home.activation.cloneAiCoding = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
  if [ ! -d "$HOME/Projects/ai-coding" ]; then
    $DRY_RUN_CMD mkdir -p "$HOME/Projects"
    $DRY_RUN_CMD ${pkgs.git}/bin/git clone \
      https://github.com/vansweej/ai-coding.git \
      "$HOME/Projects/ai-coding"
  fi
'';
```

This ensures the repo exists before any symlinks that point into it are created.

---

### Risk 2 — `cudaSupport = true` leaking to Darwin (HIGH)

**Problem:** Current `flake.nix` applies `cudaSupport = true` globally. On Darwin,
this causes mass rebuilds or evaluation failures because many packages probe for
CUDA headers.

**Fix:** `cudaSupport` is a field in each machine's metadata file. `mkHome` reads
it and passes it to `import nixpkgs`. Only `machines/oryp6.nix` sets it to `true`.

---

### Risk 3 — `nixgl.overlay` on Darwin (MEDIUM)

**Problem:** Applying the nixGL overlay on Darwin is at best dead code, at worst an
evaluation error since nixGL is Linux-specific.

**Fix:** `mkHome` conditionally applies the overlay: `overlays = if isDarwin then [] else [ nixgl.overlay ]`.

---

### Risk 4 — `systemd.user.services` on Darwin (HIGH)

**Problem:** The `systemd` home-manager module does not exist on Darwin. Having it
in a shared module causes an evaluation failure.

**Fix:** The `systemd.user.services.docker` block is placed exclusively in
`modules/machines/oryp6.nix`, which is only composed into the `oryp6`
configuration. Darwin configurations never import this module.

---

### Risk 5 — `programs.ghostty` on Darwin (LOW)

**Problem:** The home-manager `programs.ghostty` module may behave differently on
Darwin. No nixGL wrapper is needed, but the module must produce a valid config.

**Mitigation:** `programs.ghostty` stays in `modules/common.nix` with its current
settings (font, theme). These are platform-agnostic. Validate with
`nix build .#homeConfigurations.M1.activationPackage` and inspect the generated
`~/.config/ghostty/config` on the Mac after first switch.

---

## Open Questions (deferred)

These are not blockers for the current implementation but must be resolved before
adding the corresponding machines:

| Question | Impact |
|---|---|
| Username on M5? | Needed for `machines/m5.nix` metadata |
| Username on Parallels VM? | Needed for `machines/parallels.nix` metadata |
| Which host runs the Parallels VM (M1 or M5)? | Affects workflow for switching |
| Local model packages for M5 (ollama, llama.cpp, other)? | Needed for `modules/machines/m5.nix` |
| Unique packages/services for Parallels VM? | Needed for `modules/machines/parallels.nix` |
| Add `alejandra` formatter to flake? | Quality-of-life; not a blocker |
