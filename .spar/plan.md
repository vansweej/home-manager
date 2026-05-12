# Implementation Plan: ai-coding as a Nix flake

## Goal

Make ai-coding a Nix flake that exports a `packages.${system}.default` derivation
(source + `node_modules` built offline via `bun2nix`). Home-manager imports it as a
flake input, eliminating the clone activation script and `AI_CODING_MONOREPO` env var.
Tools resolve against the Nix store path by default, with an `AI_CODING_DEV=1` env var
override pointing to `~/Projects/ai-coding` for local development.

## Research outcomes

- **bun2nix (nix-community/bun2nix v2.1.0)** generates a `bun.nix` from `bun.lock` with
  `fetchurl` entries for all deps including all LanceDB platform variants. Confirmed working.
- **`bun run` from a read-only Nix store path works** — bun transpiles TypeScript in-memory,
  writes nothing to the source directory. Confirmed by test.
- **@opencode-ai/plugin** is the last remaining dependency needing `bun install` at activation
  time — it will be moved into ai-coding's `package.json` so it's baked into the Nix derivation,
  eliminating all `bun install` at switch time.

## Decisions

- No pre-commit hooks — they are unreliable in practice.
- `bun.nix` sync enforced by: (1) build-time check in the Nix derivation, (2) CI check in ai-coding.
- `opencode.json` moves from ai-coding to home-manager/opencode/ — it is config, not code.
- `@opencode-ai/plugin` moves into ai-coding's `package.json` — eliminates last bun install at switch.

---

## Execution order

| Step | Repo       | Depends on    | Risk   |
|------|------------|---------------|--------|
| 1    | ai-coding  | —             | Low    |
| 2    | ai-coding  | Step 1        | Medium |
| 3    | ai-coding  | Step 2        | Low    |
| 4    | home-manager | Step 2 merged | Low    |
| 5    | home-manager | Step 4        | Medium |
| 6    | home-manager | Step 5        | Low    |
| 7    | home-manager | Step 6        | Low    |
| 8    | both       | Steps 1–7     | —      |
| 9    | both       | Step 8 passes | Low    |

Steps 1–3 are done together on branch `feat/nix-flake` in ai-coding.
Steps 4–7 are done together on branch `feat/ai-coding-flake-input` in home-manager.

---

## Step 1 — Add @opencode-ai/plugin to ai-coding + generate bun.nix

**Repo:** ai-coding  **Branch:** `feat/nix-flake`

### 1a. Add @opencode-ai/plugin as a dependency

Add `@opencode-ai/plugin` to the root `package.json` dependencies so it is included in
the Nix-built `node_modules`. This eliminates the last remaining `bun install` at
home-manager switch time.

```bash
bun add @opencode-ai/plugin
```

Verify `bun.lock` is updated.

### 1b. Generate bun.nix

```bash
bunx bun2nix -o bun.nix
```

Commit both `bun.nix` and the updated `bun.lock` / `package.json`.

Add a `sync-nix` script to `package.json` for manual use after dependency changes:

```json
"sync-nix": "bunx bun2nix -o bun.nix"
```

Document in `AGENTS.md`: after any `bun add` / `bun remove`, run `bun run sync-nix`
and commit the updated `bun.nix` alongside `bun.lock`.

**Files changed:**
- `package.json` (add @opencode-ai/plugin dep, add sync-nix script)
- `bun.lock` (updated)
- `bun.nix` (new, generated)
- `AGENTS.md` (document sync-nix requirement)

---

## Step 2 — Create flake.nix in ai-coding

**Repo:** ai-coding  **Branch:** `feat/nix-flake`

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    bun2nix = {
      url = "github:nix-community/bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, bun2nix, ... }:
    let
      supportedSystems = [ "aarch64-darwin" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system:
        f {
          inherit system;
          pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
          b2n = bun2nix.lib.${system};
        });
    in
    {
      packages = forAllSystems ({ pkgs, b2n, system }: {
        default = pkgs.stdenv.mkDerivation {
          pname = "ai-coding";
          version = self.shortRev or "dirty";
          src = ./.;

          nativeBuildInputs = [ b2n.bun2nix-hook pkgs.bun ];

          bunDeps = b2n.fetchBunDeps {
            bunNix = ./bun.nix;
            src = ./.;
            # hash is filled after first build attempt — Nix will print the correct value
            hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
            # Patch ELF binaries on Linux so LanceDB native addon links correctly
            autoPatchelf = pkgs.stdenv.hostPlatform.isLinux;
          };

          # Build-time check: fail loudly if bun.nix is stale
          preBuild = ''
            ${pkgs.bun}/bin/bunx bun2nix -o bun.nix.check 2>/dev/null || true
            if ! diff -q bun.nix bun.nix.check > /dev/null 2>&1; then
              echo "ERROR: bun.nix is stale. Run: bun run sync-nix"
              exit 1
            fi
          '';

          buildPhase = "true";

          installPhase = ''
            mkdir -p $out
            cp -r . $out/
          '';
        };
      });

      devShells = forAllSystems ({ pkgs, ... }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            bun
            biome
            typescript
          ];
        };
      });
    };
}
```

**Notes:**
- Fill the `hash` value after the first `nix build` attempt — Nix will output the correct hash.
- Test `autoPatchelf` on oryp6 (x86_64-linux) — needed for the LanceDB `.node` native addon
  to link against the correct glibc. Add `pkgs.stdenv.cc.cc.lib` to `nativeBuildInputs` if needed.
- The `preBuild` check fails loudly if `bun.nix` is stale, catching drift locally before pushing.

**Files changed:**
- `flake.nix` (new)

**Verification (local, before merging):**
```bash
# Fill hash, then:
nix build .#default
bun run --cwd result/ skill-retrieval plan --query "test"   # must return skills
bun run --cwd result/ index-codebase --purge-only           # must exit 0
```

---

## Step 3 — CI check for bun.nix sync

**Repo:** ai-coding  **Branch:** `feat/nix-flake`

Create `.github/workflows/check-bun-nix.yml`:

```yaml
name: Check bun.nix is in sync

on:
  push:
    branches: [main]
    paths: [bun.lock, bun.nix, package.json]
  pull_request:
    paths: [bun.lock, bun.nix, package.json]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - name: Verify bun.nix matches bun.lock
        run: |
          bunx bun2nix -o bun.nix.check
          diff bun.nix bun.nix.check || \
            (echo "bun.nix is stale — run: bun run sync-nix" && exit 1)
```

**Files changed:**
- `.github/workflows/check-bun-nix.yml` (new)

---

## Step 4 — Add ai-coding as a flake input to home-manager

**Repo:** home-manager  **Branch:** `feat/ai-coding-flake-input`

### 4a. Edit flake.nix

Add `ai-coding` and `bun2nix` inputs, pass `aiCodingPkg` via `extraSpecialArgs`:

```nix
inputs = {
  nixpkgs.url     = "github:nixos/nixpkgs/nixos-unstable";
  home-manager    = { url = "github:nix-community/home-manager";
                      inputs.nixpkgs.follows = "nixpkgs"; };
  nixgl.url       = "github:guibou/nixGL";
  ai-coding       = { url = "github:vansweej/ai-coding";
                      inputs.nixpkgs.follows = "nixpkgs"; };
  bun2nix         = { url = "github:nix-community/bun2nix";
                      inputs.nixpkgs.follows = "nixpkgs"; };
};
```

In `mkHome`, extend `extraSpecialArgs`:

```nix
extraSpecialArgs = {
  inherit inputs meta;
  aiCodingPkg = inputs.ai-coding.packages.${meta.system}.default;
};
```

**Files changed:**
- `flake.nix`

---

## Step 5 — Rewrite opencode.nix

**Repo:** home-manager  **Branch:** `feat/ai-coding-flake-input`

### Remove
- `aiCodingRepo` variable
- `AI_CODING_MONOREPO` session variable
- `cloneAiCoding` activation script
- `installAiCodingDeps` activation script (fully — no more bun install at switch time)
- `opencode.json` symlink pointing into ai-coding

### Add
- `aiCodingPkg` module argument
- `AI_CODING_ROOT` session variable pointing to `"${aiCodingPkg}"`
- `opencode.json` as nix-store copy from `opencodeDir + "/opencode.json"`

### Result — key sections of new opencode.nix

```nix
{ pkgs, lib, config, aiCodingPkg, ... }:

let
  opencodeDir = ../opencode;
in
{
  home.file = {
    ".config/opencode/AGENTS.md".source   = opencodeDir + "/AGENTS.md";
    ".config/opencode/opencode.json".source = opencodeDir + "/opencode.json";
    ".config/opencode/package.json".source  = opencodeDir + "/package.json";
  }
  // agentEntries
  // skillEntries
  // commandEntries
  // toolEntries
  // binEntries;

  home.sessionVariables = {
    AI_CODING_ROOT = "${aiCodingPkg}";
  };

  home.sessionPath = [
    "$HOME/.opencode/bin"
    "$HOME/.local/bin"
  ];

  # No activation scripts — all deps are in the Nix store.
}
```

**Files changed:**
- `modules/opencode.nix`

---

## Step 6 — Move opencode.json from ai-coding to home-manager

**Repo:** home-manager  **Branch:** `feat/ai-coding-flake-input`
**Repo:** ai-coding  **Branch:** `feat/nix-flake`

Copy `ai-coding/opencode.json` → `home-manager/opencode/opencode.json`.
Remove it from ai-coding (it's config, not code — it belongs in home-manager).

**Files changed:**
- `home-manager/opencode/opencode.json` (new)
- `ai-coding/opencode.json` (deleted)

---

## Step 7 — Update tools and shell wrappers to use AI_CODING_ROOT

**Repo:** home-manager  **Branch:** `feat/ai-coding-flake-input`

### 7a. Update opencode/tools/*.ts (all three tools)

Replace:
```typescript
const monorepoRoot = process.env.AI_CODING_MONOREPO;
if (!monorepoRoot) {
  return "Error: AI_CODING_MONOREPO environment variable is not set...";
}
```

With:
```typescript
const monorepoRoot = process.env.AI_CODING_DEV === "1"
  ? `${process.env.HOME}/Projects/ai-coding`
  : process.env.AI_CODING_ROOT;

if (!monorepoRoot) {
  return (
    "Error: AI_CODING_ROOT is not set. Run: home-manager switch\n" +
    "For local development, set AI_CODING_DEV=1 (uses ~/Projects/ai-coding)."
  );
}
```

Apply to: `skill-retrieval.ts`, `codebase-retrieval.ts`, `pipeline.ts`

### 7b. Update opencode/bin/* (both shell wrappers)

Replace:
```bash
monorepo="${AI_CODING_MONOREPO:?AI_CODING_MONOREPO is not set — run: home-manager switch}"
```

With:
```bash
if [ "${AI_CODING_DEV:-}" = "1" ] && [ -d "$HOME/Projects/ai-coding" ]; then
  monorepo="$HOME/Projects/ai-coding"
else
  monorepo="${AI_CODING_ROOT:?AI_CODING_ROOT is not set — run: home-manager switch}"
fi
```

Apply to: `codebase-retrieval`, `index-codebase`

**Files changed:**
- `opencode/tools/skill-retrieval.ts`
- `opencode/tools/codebase-retrieval.ts`
- `opencode/tools/pipeline.ts`
- `opencode/bin/codebase-retrieval`
- `opencode/bin/index-codebase`

---

## Step 8 — Verification

Run on **both** aarch64-darwin (M5) and x86_64-linux (oryp6).

### 8a. ai-coding flake build

```bash
cd ~/Projects/ai-coding
nix build .#default
# Verify store path has node_modules
ls result/node_modules/@lancedb/
ls result/node_modules/@opencode-ai/
```

### 8b. Tool invocations from store path

```bash
# Skill retrieval (requires Ollama + index)
bun run --cwd result/ skill-retrieval plan --query "test"

# Codebase purge (no Ollama needed)
bun run --cwd result/ index-codebase --purge-only

# tsconfig path resolution (verifies @ai-coding/shared alias works)
bun run --cwd result/ pipeline --help 2>&1 | grep -v "Error"
```

### 8c. Fresh home-manager switch

On a clean VM (no ~/Projects/ai-coding present):
```bash
home-manager switch --flake .#M5   # or oryp6
# Must complete with no errors, no manual steps
skill-retrieval plan --query "test"   # must work immediately
```

### 8d. Dev-mode override

```bash
AI_CODING_DEV=1 skill-retrieval plan --query "test"
# Must use ~/Projects/ai-coding, not the store path
```

### 8e. autoPatchElf on Linux (oryp6 only)

```bash
bun run --cwd result/ skill-retrieval plan --query "test"
# If LanceDB fails to load the .node addon, add to derivation:
#   nativeBuildInputs = [ ... pkgs.stdenv.cc.cc.lib ];
#   autoPatchelf = true;
```

---

## Step 9 — Cleanup

### ai-coding (after Step 8 passes)

- Remove `opencode.json` (moved to home-manager)
- Update `AGENTS.md`:
  - Remove references to home-manager keeping repos in sync
  - Document `bun run sync-nix` as required step after dependency changes
  - Document `nix develop` as the standard dev workflow entry point

### home-manager (after Step 8 passes)

- Update `modules/opencode.nix` comments (remove references to ai-coding clone)
- Update `AGENTS.md`:
  - Replace `AI_CODING_MONOREPO` references with `AI_CODING_ROOT`
  - Document `AI_CODING_DEV=1` override for local development
  - Update OpenCode tools table to reflect new deployment model
- Remove `opencode/bin/index-skills` if it exists (check)
- Ensure `.gitignore` doesn't need updating

---

## Rollback plan

If VM testing (Step 8) fails:
- The home-manager branch can be reverted — `opencode.nix` with `cloneAiCoding` still works
- ai-coding only gained `flake.nix` and `bun.nix` — no breaking changes to existing workflow
- The two branches are independent; either can be reverted without affecting the other
