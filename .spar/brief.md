# Decision Brief: ai-coding as a Nix flake

## Feature
Migrate M5 and oryp6 to the Nix flake-based ai-coding setup, with full vector DB
support (skill indexing + codebase indexing), eliminating `git clone` and `bun install`
at activation time.

## Key decisions made
- ai-coding is consumed as a Nix flake input — no `git clone` or `bun install` at
  activation time on any machine.
- Two-phase Nix derivation: FOD for bun cache (hash-pinned per platform), pure build
  for `node_modules`. Only rebuilds when `bun.lock` or a `package.json` changes.
- `AI_CODING_MONOREPO` points to a read-only Nix store path — `bun run` works from
  read-only paths (verified on aarch64-linux).
- `FileBackend` (keyword routing) is the fallback when Ollama is unavailable;
  `VectorBackend` activates automatically when Ollama is reachable and the LanceDB
  index exists. No configuration needed — `createBestBackend` handles the selection.
- All workspace deps (`@lancedb/lancedb`, `apache-arrow`, `web-tree-sitter`) and native
  addons (`lancedb-linux-arm64-gnu`) are correctly installed in the Nix store via the
  existing `bun.lock`. No `package.json` changes are needed.
- Ollama runs CPU-only on VMs without GPU — sufficient for `nomic-embed-text` (274 MB,
  12 skills indexed in ~12s on CPU).
- Workflow: edit locally → push to branch → `nix flake update ai-coding` →
  `home-manager switch` on a VM to test → merge → switch on M5/oryp6. No
  `AI_CODING_DEV` escape hatch needed; VMs provide safe testing.
- `~/Projects/ai-coding` will be removed from M5/oryp6 and relocated to a separate
  dev directory to make the decoupling explicit. The Nix store path is production
  runtime; the dev clone is for active development only.
- nixGL is opt-in via `meta.nixGL = true` (oryp6 only). nixGL overlay on
  aarch64-linux is safe — lazy evaluation prevents `nixGLIntel` from being forced.
- Documentation stores are out of scope for now.
- Tools continue to use `bun run` (not compiled binaries) — LanceDB native addons
  resist `bun build --compile`.

## Validated on aarch64-linux (Parallels Ubuntu VM)
- `home-manager switch` on a fresh machine with no `~/Projects/ai-coding`: zero
  manual steps required.
- `skill-index`: 12 skills indexed end-to-end with CPU-only Ollama.
- `skill-retrieval`: `VectorBackend` active, returning semantically ranked results.
- `codebase-retrieval`: indexed and searched home-manager repo successfully.
- LanceDB native addon (`lancedb.linux-arm64-gnu.node`, 115 MB) present in store.

## Open questions
- What is the correct `x86_64-linux` FOD hash? Must be computed on oryp6 by building
  with the placeholder and capturing the `got:` value from the error output.
- Where will the ai-coding dev clone live after removing `~/Projects/ai-coding`?
- Should `~/Projects/ai-coding` be deleted or just moved on M5/oryp6?
- Does the `aarch64-darwin` FOD hash (`sha256-IhkAEL/j+...`) still match the current
  `bun.lock`? Needs verification on M5 during the switch.

## Rejected alternatives
- **Adding `@lancedb/lancedb-linux-arm64-gnu` to root `optionalDependencies`** —
  investigation showed it was already resolved by bun from the existing lockfile;
  the native addon is present in the store.
- **`AI_CODING_DEV` env var for local development** — unnecessary; the push → flake
  update → switch workflow is sufficient, and VMs provide safe testing.
- **Documentation store package** — deferred; skill indexing and codebase indexing
  cover current needs.
- **Merging ai-coding into home-manager repo** — rejected; repos stay decoupled via
  flake input.
- **Compiled binaries (`bun build --compile`)** — rejected; LanceDB native addons and
  dynamic pipeline imports don't work with static compilation.

## Risks identified
1. **oryp6 build will fail** — `x86_64-linux` FOD hash is still a placeholder
   (`sha256-AAAA...`). Must be computed before switching. **Blocker for oryp6.**
2. **Stale `aarch64-darwin` FOD hash** — if `bun.lock` changed since the hash was
   computed, the M5 build will fail with a hash mismatch. Easy to recompute from the
   `got:` line. Severity: medium.
3. **Cached `AI_CODING_MONOREPO` in open shells** — after switching, existing terminal
   sessions still have the old `~/Projects/ai-coding` path. New shells pick up the
   store path automatically. Severity: low.
4. **`dontFixup = true` disables all Nix fixup** — not just patchelf on LanceDB, but
   also stripping and other post-install steps on every file. Store path is slightly
   larger than necessary. Severity: low.
5. **VectorBackend ranking quality** — with a short query like `--action edit`, the
   embedding matches on "edit" broadly, returning `documenter` above `programmer`.
   Richer queries sharpen results. Requires experience before tuning. Severity: low.

## Recommended next steps

### Phase 1 — Merge ai-coding
1. Merge `feat/nix-flake` → `main` in ai-coding.

### Phase 2 — Update home-manager to point at ai-coding main
2. On `feat/ai-coding-flake-input` branch: change `home-manager/flake.nix` line 12
   from `github:vansweej/ai-coding/feat/nix-flake` to `github:vansweej/ai-coding`.
3. Run `nix flake update ai-coding` to re-pin `flake.lock` to the merged `main` commit.
4. Commit both `flake.nix` and `flake.lock` together, push.

### Phase 3 — Switch M5 (lowest risk, do first)
5. Merge `feat/ai-coding-flake-input` → `main` in home-manager.
6. Pull `main` on M5, verify ai-coding package builds in isolation (see Migration
   instructions below), then run `home-manager switch --flake .#M5`.
7. Verify: `echo $AI_CODING_MONOREPO` points to `/nix/store/...`,
   `bun run --cwd $AI_CODING_MONOREPO skill-retrieval --action edit` works.
   If the `aarch64-darwin` FOD hash is stale, the build will fail with a `got:` line —
   update the hash in ai-coding, push, `nix flake update ai-coding`, retry.

### Phase 4 — Switch oryp6 (requires hash computation)
8. On oryp6: pull `main`, build ai-coding package in isolation to capture the
   `x86_64-linux` FOD hash (see Migration instructions below).
9. Update `ai-coding/flake.nix` `x86_64-linux` hash, commit, push to `main`.
10. On any machine: `nix flake update ai-coding` in home-manager, commit
    `flake.lock`, push.
11. On oryp6: pull, `home-manager switch --flake .#oryp6`.

### Phase 5 — Cleanup
12. Remove `~/Projects/ai-coding` from M5 and oryp6, relocate dev clone.

## Migration instructions

### Verifying the ai-coding package before full activation

Before running `home-manager switch` on a machine, first build the ai-coding
package in isolation. This is faster than evaluating the full home-manager config
and gives immediate feedback on FOD hash issues without triggering a full
activation failure.

**On M5 (aarch64-darwin) — after Phase 2, before Phase 3 step 6:**
```bash
nix build github:vansweej/ai-coding#packages.aarch64-darwin.default
```
- If it succeeds: the `aarch64-darwin` hash is correct, proceed to `home-manager switch`.
- If it fails with a hash mismatch: copy the `got:` hash, update
  `ai-coding/flake.nix` line 22, commit, push. Then re-run.

**On oryp6 (x86_64-linux) — replaces Phase 4 step 8:**
```bash
nix build github:vansweej/ai-coding#packages.x86_64-linux.default
```
- This will fail because the `x86_64-linux` hash is a placeholder.
- Copy the `got:` hash from the error output.
- Update `ai-coding/flake.nix` line 23, commit, push to `main`.
- On any machine: `nix flake update ai-coding` in home-manager, commit `flake.lock`, push.
- On oryp6: pull, then `home-manager switch --flake .#oryp6`.

### Post-switch verification checklist

Run these on each machine after a successful `home-manager switch`:

```bash
# 1. Confirm AI_CODING_MONOREPO points to the Nix store (open a new shell first)
echo $AI_CODING_MONOREPO
# Expected: /nix/store/...-ai-coding-0.1.0

# 2. Confirm skill-retrieval works (FileBackend — no Ollama needed)
bun run --cwd $AI_CODING_MONOREPO skill-retrieval --action edit
# Expected: returns programmer skill content

# 3. Confirm LanceDB native addon is present
ls $AI_CODING_MONOREPO/packages/skills/node_modules/@lancedb/lancedb
# Expected: symlink to hoisted .bun cache

# 4. If Ollama is running: confirm VectorBackend works
bun run --cwd $AI_CODING_MONOREPO skill-index
bun run --cwd $AI_CODING_MONOREPO skill-retrieval --action edit
# Expected: returns multiple skills ranked by relevance
```

### Rollback

If `home-manager switch` succeeds but something is broken, roll back to the
previous generation:

```bash
home-manager generations          # list available generations
home-manager switch --flake .#M5  # re-run with the previous main branch
```

Or check out the pre-merge `main` commit and switch:

```bash
git log --oneline -5              # find the pre-merge commit
git checkout <commit>
home-manager switch --flake .#M5
git checkout main                 # return to main after verifying
```
