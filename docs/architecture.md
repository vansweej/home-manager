# Architecture

This repository uses a layered module composition model so that multiple machines
can be managed from a single flake without conditionals scattered across shared
files.

## Repository layout

```
flake.nix                          # mkHome helper; all homeConfigurations outputs
machines/
  oryp6.nix                        # Plain attrset: system, username, homeDir, flags
  m1.nix                           # Plain attrset: system, username, homeDir, flags
  m5.nix                           # Plain attrset: system, username, homeDir, flags
modules/
  common.nix                       # Universal config — all machines; imports opencode.nix
  opencode.nix                     # OpenCode config — auto-discovery, activation, session vars
  linux.nix                        # Linux-only config
  darwin.nix                       # macOS-only config
  machines/
    oryp6.nix                      # oryp6-specific config
    m1.nix                         # M1-specific config
    m5.nix                         # M5-specific config
opencode/                          # OpenCode files deployed to ~/.config/opencode/
  agents/                          # Agent .md files (auto-discovered)
  skills/                          # Skill subdirectories, each with SKILL.md (auto-discovered)
  commands/                        # Command .md files (auto-discovered)
  tools/                           # Tool implementations (auto-discovered; shell out to ai-coding at runtime)
  bin/                             # CLI wrapper scripts (auto-discovered; deployed to ~/.local/bin/)
nvim/                              # Neovim plugin files (live-symlinked)
```

## Module layers

Each machine profile is composed from exactly three layers:

```
modules/common.nix          ← all machines (imports opencode.nix)
      +
modules/linux.nix           ← x86_64-linux machines only
  OR
modules/darwin.nix          ← aarch64-darwin machines only
      +
modules/machines/<name>.nix ← that machine only
```

`opencode.nix` is imported by `common.nix` and handles all OpenCode-specific
configuration: auto-discovered agents, skills, commands, and tools; session
variables; session path; and the `cloneAiCoding` + `installAiCodingDeps`
activation scripts.

## Machine metadata files

Each machine has a **plain Nix attrset** file under `machines/`:

```nix
# machines/oryp6.nix
{
  system = "x86_64-linux";
  username = "vansweej";
  homeDirectory = "/home/vansweej";
  stateVersion = "25.11";
  cudaSupport = true;
}
```

This file is imported by `flake.nix` *before* `pkgs` is instantiated — it is not
a home-manager module. This avoids the chicken-and-egg problem where `system` must
be known to create `pkgs`, but `pkgs` must exist before modules are evaluated.

## The `mkHome` helper

`flake.nix` defines a `mkHome` function that wires everything together:

```nix
mkHome = machineMetaPath: machineModulePath:
  let
    meta = import machineMetaPath;           # 1. read plain attrset
    isDarwin = builtins.match ".*-darwin" meta.system != null;

    pkgs = import nixpkgs {
      system = meta.system;                  # 2. correct architecture
      config.allowUnfree = true;
      config.cudaSupport = meta.cudaSupport; # 3. per-machine CUDA flag
      overlays = if isDarwin then []         # 4. nixGL on Linux only
                 else [ nixgl.overlay ];
    };
  in
  home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit inputs meta; };
    modules = [
      { home.username = meta.username;       # 5. identity from metadata
        home.homeDirectory = meta.homeDirectory;
        home.stateVersion = meta.stateVersion; }
      ./modules/common.nix                   # 6. universal
    ]
    ++ (if isDarwin then [ ./modules/darwin.nix ]
                    else [ ./modules/linux.nix ]) # 7. platform
    ++ [ machineModulePath ];                # 8. machine-specific
  };
```

Key properties:

- **No hardcoded identity in any module** — `home.username`, `home.homeDirectory`,
  and `home.stateVersion` are always injected from the metadata file.
- **Per-machine `pkgs`** — each configuration gets its own nixpkgs instantiation
  with the correct `system` and `cudaSupport`. There is no shared global `pkgs`.
- **Conditional overlays** — `nixgl.overlay` is only applied on Linux. Applying it
  on Darwin would cause evaluation errors since nixGL is Linux-specific.
- **`systemd` never evaluated on Darwin** — the Docker systemd service lives
  exclusively in `modules/machines/oryp6.nix`, which is never imported by any
  Darwin configuration.

## Activation script ordering

Three activation scripts run on every `home-manager switch`:

| Script | Module | Order | Purpose |
|---|---|---|---|
| `cloneAiCoding` | `opencode.nix` | `entryBefore [ "writeBoundary" ]` | Clones `~/Projects/ai-coding` if absent |
| `installAiCodingDeps` | `opencode.nix` | After `cloneAiCoding`, before `writeBoundary` | Installs monorepo root + `.opencode/` deps with lockfile-hash stamp |
| `bootstrapNvim` | `common.nix` | `entryBefore [ "writeBoundary" ]` | Bootstraps `~/.config/nvim` from LazyVim starter |

All three run **before** `writeBoundary` — the phase where home-manager creates
`mkOutOfStoreSymlink` symlinks. This ensures symlinks pointing into
`~/Projects/ai-coding/` and `~/Projects/home-manager/` are never dangling on a
fresh machine's first activation.

`installAiCodingDeps` uses a SHA-256 hash of `bun.lock` stored in
`node_modules/.hm-install-stamp` to skip redundant installs. The stamp is written
only on success — a failed install is retried on the next switch without blocking
the rest of the activation.

## `mkOutOfStoreSymlink` vs store paths

Two kinds of file management are used:

| Method | When used | Behaviour |
|---|---|---|
| Store path (`.source = ./path`) | Static files: skills, agents, commands, bin wrappers | Copied into Nix store; requires `home-manager switch` to update |
| `mkOutOfStoreSymlink` | Live files: nvim plugins, `opencode.json`, OpenCode tools | Symlinked to the repo/ai-coding path; updates immediately on disk |

OpenCode tools (`pipeline.ts`, `skill-retrieval.ts`, `codebase-retrieval.ts`) use
`mkOutOfStoreSymlink` pointing to `~/Projects/home-manager/opencode/tools/` because
bun needs to resolve `node_modules` relative to the file — copying into the Nix
store would break that resolution. The tools are full implementations that delegate
to the ai-coding monorepo at runtime via subprocess (`bun run <script> --cwd
$AI_CODING_MONOREPO`). They do not import code from ai-coding.

## Adding a new machine

See [adding-a-machine.md](adding-a-machine.md) for the step-by-step guide.
