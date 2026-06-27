# Brief: Fix cerebrum memory MCP — shortest path to working persistence

## Feature
Make the cerebrum two-tier memory MCP server actually start, stay connected,
and persist memories durably across session restarts on oryp6.

## My opinion — what happened and the shortest fix

### Root cause (proven, not speculated)

The pinned cerebrum binary (`f59c5dff`) at
`/nix/store/ginzyw8rvdakd41dvczsh2mxnpxj8gzk-cerebrum/bin/cerebrum`
calls `MemoryOrchestrator::from_config(&Config::default()).await?` in `main.rs`.

`Config::default()` points at real Ollama (`http://localhost:11434`) with
`nomic-embed-text` at 768 dimensions. If Ollama is not running or the model
is not pulled, `from_config()` returns `Err`, `main` exits, the stdio pipe
closes, and OpenCode logs:

```
level=WARN message="MCP connection closed" server=cerebrum
```

This is confirmed in today's log (2026-06-27T00:07:06 and 00:48:01). The
server spawns, fails to connect to Ollama at startup, exits, and the memory
tools vanish from the session. The LanceDB table on disk
(`~/.local/share/cerebrum/data/cerebrum/memories.lance/`) is intact — the
server just cannot boot without its embedder backend.

### What is NOT broken

- Home-manager wiring: correct since commit `d74aa47`
- Nix overlay merge: `oryp6.nix:12-16` folds cerebrum into opencode.json ✓
- Deployed config: `~/.config/opencode/opencode.json` contains `mcp.cerebrum` ✓
- Store binary: exists, wrapper creates `~/.local/share/cerebrum`, cd's in ✓
- Data dir + LanceDB table: present, has `__manifest/` + `memories.lance/` ✓
- OpenCode version: 1.17.7, loads the config, attempts the spawn ✓

### What IS broken

Ollama is either not running as a service on oryp6, or `nomic-embed-text` is
not pulled. There is NO managed Ollama service in the home-manager config for
oryp6. The server's hard startup dependency has no guarantee of being
satisfied.

### Why the AGENTS.md docs said "MockEmbedder (offline)"

They lied. They described an earlier design intent that was never shipped. The
actual `main.rs` at the pinned commit uses `from_config()` (real Ollama), not
`MockEmbedder::new()`. The README itself contradicts itself — one section says
"no external services" while another says "Ollama is a hard dependency." The
code is the truth: real Ollama, real persistence, hard dependency.

---

## The shortest path (my recommendation)

Three things must be true simultaneously:
1. Ollama is running on oryp6 as a resident user service
2. `nomic-embed-text` model is pulled (one-time)
3. OpenCode is restarted cleanly so it re-spawns cerebrum against a live Ollama

That's it. No code changes to cerebrum. No embedder swaps. No `:memory:`.
The server already does what you want — real durable persistence with real
semantic embeddings. It just needs its backend running.

### Implementation (one commit)

**File: `modules/machines/oryp6.nix`**

Add Ollama as a managed user service (same pattern as Docker and
athenaeum-watch already in this file):

```nix
home.packages = with pkgs; [
  docker
  slirp4netns
  rootlesskit
  ollama          # ← ADD
];

# Ollama embedding server — hard startup dependency of cerebrum-mcp.
# Must be running before OpenCode spawns the memory MCP server, or
# MemoryOrchestrator::from_config() fails and the server exits immediately.
# Model pull (one-time): ollama pull nomic-embed-text
systemd.user.services.ollama = {
  Unit = {
    Description = "Ollama inference server (cerebrum embeddings backend)";
    After = [ "default.target" ];
  };
  Service = {
    Type = "simple";
    ExecStart = "${pkgs.ollama}/bin/ollama serve";
    Restart = "always";
    Environment = [
      "OLLAMA_HOST=127.0.0.1:11434"
    ];
  };
  Install = {
    WantedBy = [ "default.target" ];
  };
};
```

**File: `AGENTS.md`**

Fix lines 283-289. Replace the MockEmbedder lie with reality:

```markdown
The `cerebrum` input is updated with `nix flake update cerebrum`. The store-built
wrapped binary creates `~/.local/share/cerebrum` on first run and cd's into it, so
no activation script or cwd pinning is needed. Data persists as a LanceDB table at
`~/.local/share/cerebrum/data/cerebrum/memories.lance`. The binary uses real Ollama
embeddings (`nomic-embed-text`, 768-dim) via `Config::default()`. **Ollama is a HARD
startup dependency** — if it is not running at `localhost:11434` with the model
pulled, `from_config()` fails and the server exits immediately. Ollama is managed as
a systemd user service in `modules/machines/oryp6.nix`. One-time setup after first
deploy: `ollama pull nomic-embed-text`.
```

Also update the Key Packages table — add Ollama row, fix cerebrum row:

```
| `ollama` | Package + `systemd.user.services` | `modules/machines/oryp6.nix` | Embedding backend for cerebrum; serves nomic-embed-text; oryp6 only |
| `cerebrum` | MCP server (via `cerebrum-wrapped`) | `modules/cerebrum.nix` | Two-tier agent memory (Synapse + Cortex); all machines; real Ollama embeddings (768-dim); hard-requires Ollama service |
```

### Post-deploy steps (manual, one-time)

```bash
# 1. Deploy
git add modules/machines/oryp6.nix AGENTS.md
nix build .#homeConfigurations.oryp6.activationPackage
home-manager switch --flake .#oryp6

# 2. Confirm Ollama is running
systemctl --user status ollama

# 3. Pull the model (one-time, weights live in ~/.ollama)
ollama pull nomic-embed-text

# 4. Kill ALL OpenCode instances (the daemon caches MCP state at boot)
# Then relaunch OpenCode in any project

# 5. Verify cerebrum stays connected (no "connection closed" after restart)
grep -i cerebrum ~/.local/share/opencode/log/opencode.log | tail -5

# 6. Durability proof
# In OpenCode: call cerebrum_remember with "PERSISTENCE-TEST-2026-06-27"
# Quit OpenCode fully (server dies)
# Relaunch OpenCode: call cerebrum_recall with "PERSISTENCE-TEST"
# If the memory comes back → done. Working durable memory.
```

---

## Key decisions made

- Real Ollama embeddings — not MockEmbedder, not offline, not `:memory:`
- Ollama managed as a systemd user service on oryp6 (same pattern as Docker)
- No changes to the cerebrum binary or upstream repo
- No changes to opencode.json or cerebrum.nix — the MCP registration is correct
- AGENTS.md docs corrected to match reality

## Rejected alternatives

| Alternative | Why rejected |
|---|---|
| Switch to `MockEmbedder` / offline mode | Defeats the entire 48-hour persistence effort; gives hash-based fake embeddings, no real semantic search |
| Run Ollama manually (no service) | Fragile; forgets after reboot; the exact failure mode we're fixing |
| Add Ollama check to the wrapper script | Masks the problem; server would block or busy-wait; doesn't fix the startup ordering |
| Change `from_config()` to fall back to MockEmbedder | Degrades silently; user thinks they have real memory but gets garbage embeddings |

## Risks identified

1. **`pkgs.ollama` may pull CUDA/ROCm dependencies on oryp6** — oryp6 has
   `cudaSupport = true` in its machine metadata. If nixpkgs' ollama derivation
   respects that flag, the closure size grows significantly. Acceptable for a
   machine with a GPU, but verify `nix build` time doesn't explode.

2. **Model pull is stateful and outside Nix** — `~/.ollama/models` is mutable
   state not managed by home-manager. If wiped, cerebrum dies silently again
   until re-pulled. The AGENTS.md note documents this. A future improvement
   could add a health-check activation script.

3. **Boot race on slow machines** — Ollama's `WantedBy = default.target`
   should start before the user opens a terminal, but if OpenCode auto-starts
   (e.g. from a session restore), it might spawn cerebrum before Ollama's
   socket is ready. The circuit breaker in cerebrum-core *should* handle
   transient unavailability, but `from_config()` currently hard-fails. A retry
   in the wrapper (sleep + loop) would harden this further — not in scope now.

4. **M1 and M5 also run cerebrum** — they have the same hard Ollama
   dependency. If you want memory on those machines too, they need the same
   fix (launchd agent for Ollama + model pull). Not blocking oryp6 fix.

## Recommended next steps (for the build agent)

1. Add `ollama` package + systemd service to `modules/machines/oryp6.nix`
2. Fix AGENTS.md docs (MockEmbedder → real Ollama)
3. `git add` → `nix build .#homeConfigurations.oryp6.activationPackage` → verify
4. Commit: `feat: add managed Ollama service as cerebrum embedding backend`
5. The user handles: `home-manager switch`, `ollama pull nomic-embed-text`,
   restart OpenCode, run the durability test
