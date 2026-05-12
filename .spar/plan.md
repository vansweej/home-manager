# Implementation Plan: ai-coding as a Nix flake (v2)

## Goal

Make ai-coding a Nix flake that exports a `packages.${system}.default` derivation
(source + `node_modules` built offline via `bun2nix`). Home-manager imports it as a
flake input, eliminating the clone activation script, all `bun install` activation
scripts, and the `AI_CODING_MONOREPO` env var. Tools resolve against the Nix store
path by default, with `AI_CODING_DEV=1` pointing shell wrappers to `~/Projects/ai-coding`
for local development.

## Research outcomes

- **bun2nix (nix-community/bun2nix v2.1.0)** generates a `bun.nix` from `bun.lock` with
  `fetchurl` entries for all deps including all LanceDB platform variants. Confirmed working.
- **`bun run` from a read-only Nix store path works** — bun transpiles TypeScript in-memory,
  writes nothing to the source directory. Confirmed by test.

## Key decisions

- **Tools move to ai-coding** — `skill-retrieval.ts`, `codebase-retrieval.ts`, `pipeline.ts`
  relocate from `home-manager/opencode/tools/` to `ai-coding/tools/`. They ship inside the
  Nix derivation alongside `node_modules/@opencode-ai/plugin/`, so bun resolves imports
  naturally. Deployed as nix-store copies (not symlinks) — tool edits are rare and go through
  the normal commit → push → flake update → switch cycle.
- **`opencode.json` moves to home-manager** — it is config, not code.
- **`@opencode-ai/plugin` added to ai-coding's `package.json`** — baked into the Nix derivation.
- **All activation scripts eliminated** — no `cloneAiCoding`, no `installAiCodingDeps`, no
  `bun install` at switch time. Zero network calls during `home-manager switch`.
- **`home-manager/opencode/package.json`** deleted — it only existed to provide
  `@opencode-ai/plugin` for the tools, which now live in ai-coding.
- **No pre-commit hooks** — `bun.nix` sync enforced by two safety nets:
  (1) build-time check in the Nix derivation using the `bun2nix` binary from the flake input,
  (2) CI check in ai-coding on every PR touching `bun.lock` or `bun.nix`.
- **`bunx` not used in the Nix sandbox** — the sandbox has no network access; `bun2nix`
  is invoked via its binary from the flake input instead.
- **Dev-mode override** — `AI_CODING_DEV=1` makes shell wrappers (`bin/*`) use
  `~/Projects/ai-coding` instead of the Nix store path. Tools (deployed as nix-store copies)
  are not affected — tool edits are rare and go through the flake update cycle.

---

## Execution order

| Step | Repo         | Depends on    | Risk   |
|------|--------------|---------------|--------|
| 1    | ai-coding    | —             | Low    |
| 2    | ai-coding    | Step 1        | Medium |
| 3    | ai-coding    | Step 2        | Low    |
| 4    | home-manager | Step 2 merged | Low    |
| 5    | home-manager | Step 4        | Medium |
| 6    | home-manager | Step 5        | Low    |
| 7    | both         | Steps 1–6     | —      |
| 8    | both         | Step 7 passes | Low    |

Steps 1–3 are done together on branch `feat/nix-flake` in ai-coding.
Steps 4–6 are done together on branch `feat/ai-coding-flake-input` in home-manager.

---

## Step 1 — Relocate tools + add @opencode-ai/plugin + generate bun.nix

**Repo:** ai-coding  **Branch:** `feat/nix-flake`

### 1a. Create tools/ directory in ai-coding

Move the three OpenCode tool files from home-manager into ai-coding:

```
ai-coding/tools/
  skill-retrieval.ts     ← from home-manager/opencode/tools/
  codebase-retrieval.ts  ← from home-manager/opencode/tools/
  pipeline.ts            ← from home-manager/opencode/tools/
```

Update all three tools — replace `AI_CODING_MONOREPO` with `AI_CODING_ROOT`:

```typescript
// Before
const monorepoRoot = process.env.AI_CODING_MONOREPO;
if (!monorepoRoot) {
  return "Error: AI_CODING_MONOREPO environment variable is not set...";
}

// After
const monorepoRoot = process.env.AI_CODING_ROOT;
if (!monorepoRoot) {
  return (
    "Error: AI_CODING_ROOT is not set. Run: home-manager switch\n" +
    "For local development, set AI_CODING_DEV=1."
  );
}
```

Since the tools now live inside ai-coding alongside `node_modules/@opencode-ai/plugin/`,
bun resolves the import naturally — no `mkOutOfStoreSymlink` or extra resolution config needed.

### 1b. Add @opencode-ai/plugin as a dependency

```bash
bun add @opencode-ai/plugin
```

Verify `bun.lock` is updated.

### 1c. Generate bun.nix

```bash
bunx bun2nix -o bun.nix
```

Add a `sync-nix` script to `package.json` for use after dependency changes:

```json
"sync-nix": "bunx bun2nix -o bun.nix"
```

Document in `AGENTS.md`: after any `bun add` / `bun remove`, run `bun run sync-nix`
and commit the updated `bun.nix` alongside `bun.lock`.

**Files changed:**
- `tools/skill-retrieval.ts` (new — moved + updated from home-manager)
- `tools/codebase-retrieval.ts` (new — moved + updated from home-manager)
- `tools/pipeline.ts` (new — moved + updated from home-manager)
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
        });
    in
    {
      packages = forAllSystems ({ pkgs, system }: {
        default = pkgs.stdenv.mkDerivation {
          pname = "ai-coding";
          version = self.shortRev or "dirty";
          src = ./.;

          nativeBuildInputs = [
            bun2nix.packages.${system}.bun2nix-hook
            pkgs.bun
          ];

          bunDeps = bun2nix.packages.${system}.fetchBunDeps {
            bunNix = ./bun.nix;
            src = ./.;
            # Fill after first build attempt — Nix prints the correct hash
            hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          };

          # Build-time staleness check — uses bun2nix binary from the flake input
          # so no network access is needed in the sandbox.
          preBuild = ''
            ${bun2nix.packages.${system}.default}/bin/bun2nix -o bun.nix.check
            if ! diff -q bun.nix bun.nix.check > /dev/null 2>&1; then
              echo "ERROR: bun.nix is stale. Run: bun run sync-nix"
              exit 1
            fi
            rm bun.nix.check
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
- The `hash` placeholder must be filled after the first `nix build` attempt — Nix will
  print the correct value.
- The `preBuild` check invokes `bun2nix` from the flake input binary, not via `bunx`,
  so it works without network access in the sandbox.
- `autoPatchelf` may be needed on Linux for the LanceDB native addon. Test on oryp6.
  If the `.node` addon fails to load, add to the derivation:
  ```nix
  nativeBuildInputs = [ ... pkgs.autoPatchelfHook pkgs.stdenv.cc.cc.lib ];
  ```
- The exact `bun2nix` attribute paths (`packages.${system}.bun2nix-hook`,
  `packages.${system}.fetchBunDeps`, `packages.${system}.default`) must be verified
  against the bun2nix flake outputs during implementation. Run `nix flake show
  github:nix-community/bun2nix` to inspect the actual attribute names.

**Files changed:**
- `flake.nix` (new)

**Verification (local, before merging):**
```bash
cd ~/Projects/ai-coding
nix build .#default
ls result/node_modules/@lancedb/          # all platform variants present
ls result/node_modules/@opencode-ai/      # plugin present
ls result/tools/                           # tools present
bun run --cwd result/ skill-retrieval plan --query "test"   # returns skills
bun run --cwd result/ index-codebase --purge-only           # exits 0
bun run --cwd result/ pipeline --help                       # parses without import errors
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

Edit `flake.nix` — add `ai-coding` input and pass `aiCodingPkg` via `extraSpecialArgs`:

```nix
inputs = {
  nixpkgs.url  = "github:nixos/nixpkgs/nixos-unstable";
  home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  nixgl.url    = "github:guibou/nixGL";
  ai-coding    = {
    url = "github:vansweej/ai-coding";
    inputs.nixpkgs.follows = "nixpkgs";
  };
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
- `aiCodingRepo` variable (line 5)
- `AI_CODING_MONOREPO` session variable
- `cloneAiCoding` activation script
- `installAiCodingDeps` activation script (fully — zero bun install at switch time)
- `opencode.json` symlink pointing into ai-coding
- `package.json` deployment (no longer needed)
- `toolEntries` using `mkOutOfStoreSymlink` into home-manager or ai-coding

### Add
- `aiCodingPkg` module argument
- `AI_CODING_ROOT` session variable pointing to `"${aiCodingPkg}"`
- `opencode.json` as nix-store copy from `opencodeDir + "/opencode.json"`
- `toolEntries` deploying from `"${aiCodingPkg}/tools/${name}"` as nix-store copies

### Key sections of the new opencode.nix

```nix
{ pkgs, lib, config, aiCodingPkg, ... }:

let
  opencodeDir = ../opencode;

  # ── Auto-discover tools ─────────────────────────────────────────────────────
  # Tools now live in ai-coding/tools/ and are deployed from the Nix store path.
  # Deployed as nix-store copies — edits go through commit → flake update → switch.
  toolFiles = builtins.readDir ("${aiCodingPkg}/tools");
  toolEntries = lib.mapAttrs' (name: _:
    lib.nameValuePair
      ".config/opencode/tools/${name}"
      { source = "${aiCodingPkg}/tools/${name}"; }
  ) (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".ts" n) toolFiles);

in
{
  home.file = {
    ".config/opencode/AGENTS.md".source    = opencodeDir + "/AGENTS.md";
    ".config/opencode/opencode.json".source = opencodeDir + "/opencode.json";
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

  # No activation scripts — all deps are in the Nix store. Zero network calls at switch.
}
```

**Files changed:**
- `modules/opencode.nix`

---

## Step 6 — Remaining home-manager changes

**Repo:** home-manager  **Branch:** `feat/ai-coding-flake-input`

### 6a. Move opencode.json from ai-coding to home-manager

Copy `ai-coding/opencode.json` → `home-manager/opencode/opencode.json`.
(The deletion from ai-coding happens in the ai-coding branch — coordinate timing.)

### 6b. Update shell wrappers to use AI_CODING_ROOT + dev override

In `opencode/bin/codebase-retrieval` and `opencode/bin/index-codebase`, replace:

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

### 6c. Delete home-manager/opencode/tools/

The three tool files are now in ai-coding. Remove:
- `opencode/tools/skill-retrieval.ts`
- `opencode/tools/codebase-retrieval.ts`
- `opencode/tools/pipeline.ts`

### 6d. Delete home-manager/opencode/package.json

No longer needed — `@opencode-ai/plugin` is now in ai-coding's `node_modules`.

**Files changed:**
- `opencode/opencode.json` (new — moved from ai-coding)
- `opencode/bin/codebase-retrieval` (updated)
- `opencode/bin/index-codebase` (updated)
- `opencode/tools/skill-retrieval.ts` (deleted)
- `opencode/tools/codebase-retrieval.ts` (deleted)
- `opencode/tools/pipeline.ts` (deleted)
- `opencode/package.json` (deleted)

---

## Step 7 — Verification

Run on **both** aarch64-darwin (M5) and x86_64-linux (oryp6).

### 7a. ai-coding flake build

```bash
cd ~/Projects/ai-coding
nix build .#default
ls result/node_modules/@lancedb/        # all platform variants present
ls result/node_modules/@opencode-ai/    # plugin present
ls result/tools/                         # all three tools present
```

### 7b. Tool invocations from store path

```bash
# Skill retrieval (requires Ollama + index)
bun run --cwd result/ skill-retrieval plan --query "test"

# Codebase purge (no Ollama needed)
bun run --cwd result/ index-codebase --purge-only

# tsconfig path aliases resolve correctly (@ai-coding/shared, etc.)
bun run --cwd result/ pipeline --help

# bun.nix staleness check triggers correctly
# (verify by temporarily editing bun.nix and running nix build — must fail)
```

### 7c. Fresh home-manager switch

On a clean VM (no ~/Projects/ai-coding present):
```bash
home-manager switch --flake .#M5    # aarch64-darwin
home-manager switch --flake .#oryp6 # x86_64-linux
# Must complete with no errors, no manual steps, no network calls (beyond flake fetch)
skill-retrieval plan --query "test"   # must work immediately
index-codebase --purge-only           # must work immediately
```

### 7d. Dev-mode override for shell wrappers

```bash
AI_CODING_DEV=1 index-codebase --purge-only
# Must use ~/Projects/ai-coding, not the store path
# Verify by checking which bun.lock is loaded (add a temporary debug echo if needed)
```

### 7e. autoPatchElf on Linux (oryp6 only)

```bash
bun run --cwd result/ skill-retrieval plan --query "test"
# If LanceDB .node addon fails to load, add to flake.nix derivation:
#   nativeBuildInputs = [ ... pkgs.autoPatchelfHook pkgs.stdenv.cc.cc.lib ];
# Then rebuild and retest.
```

---

## Step 8 — Cleanup

### ai-coding (after Step 7 passes)

- Delete `opencode.json` (moved to home-manager)
- Update `AGENTS.md`:
  - Remove the rule about keeping home-manager in sync when editing agents/skills/commands
    (that sync is now one-way: home-manager deploys from the flake input)
  - Document `bun run sync-nix` as required step after dependency changes
  - Document `nix develop` as the standard dev workflow entry point
  - Remove `AI_CODING_MONOREPO` references

### home-manager (after Step 7 passes)

- Update `modules/opencode.nix` inline comments (remove references to ai-coding clone,
  ai-coding repo path, mkOutOfStoreSymlink for tools)
- Update `AGENTS.md`:
  - Replace `AI_CODING_MONOREPO` with `AI_CODING_ROOT` throughout
  - Document `AI_CODING_DEV=1` override for shell wrapper development
  - Update the OpenCode tools table to reflect tools now live in ai-coding/tools/
  - Remove the "Adding a new OpenCode tool" section that references marker files
  - Add a new "Adding a new OpenCode tool" section: edit in ai-coding, commit, push,
    run `nix flake update ai-coding` in home-manager, run `home-manager switch`

---

## Rollback plan

If VM testing (Step 7) fails:
- The home-manager branch can be reverted — `opencode.nix` with `cloneAiCoding` still works.
- ai-coding gained `flake.nix`, `bun.nix`, and `tools/` — no breaking changes to its
  existing `bun run` workflow.
- The two branches are independent; either can be reverted without affecting the other.
