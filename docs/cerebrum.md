# Cerebrum MCP Server — Operational Runbook

Cerebrum is a two-tier agent memory subsystem deployed as a Model Context Protocol (MCP) server. It provides semantic search across short-term (Synapse) and long-term (Cortex) memory tiers, with real Ollama embeddings initialized lazily on first use.

---

## What It Does

- **Synapse Tier:** Fast, in-memory short-term memory with semantic search (session-scoped)
- **Cortex Tier:** Persistent long-term memory backed by LanceDB with vector embeddings
- **Blended Recall:** Unified semantic search across both tiers, ranked by salience
- **Automatic Promotion:** Memories promoted from Synapse to Cortex based on importance score
- **Lazy Ollama:** Real embeddings via Ollama HTTP API (nomic-embed-text), contacted only on first `remember()`/`recall()` call

---

## Data Location

- **Data Directory:** `~/.local/share/cerebrum/`
- **LanceDB Store:** `~/.local/share/cerebrum/data/cerebrum/memories.lance`
- **Created on first run:** The wrapped binary creates the directory automatically

---

## Tools Registered

All agents have access to the following MCP tools (no per-agent gating):

| Tool | Purpose |
|------|---------|
| `cerebrum_remember` | Store a memory in Synapse with optional salience score (0.0–1.0) |
| `cerebrum_recall` | Search both tiers for memories matching a query |
| `cerebrum_recall_by_scope` | Search with scope filtering (global, user, agent, session) |
| `cerebrum_memorize` | Promote a memory from Synapse to Cortex (long-term) |
| `cerebrum_forget` | Delete a memory from both tiers |
| `cerebrum_end_session` | Clear Synapse and auto-promote high-salience memories to Cortex |

---

## Health Check

### Verify Cerebrum is Registered

Check that the MCP server is registered in OpenCode:

```bash
# View the active opencode.json
cat ~/.config/opencode/opencode.json | jq '.mcp.cerebrum'
```

Expected output:
```json
{
  "type": "local",
  "command": ["/nix/store/.../bin/cerebrum"],
  "enabled": true
}
```

### Verify Tools Are Available

In any OpenCode agent (e.g., `build`), run:

```bash
# List available tools
tools
```

You should see `cerebrum_remember`, `cerebrum_recall`, `cerebrum_recall_by_scope`, `cerebrum_memorize`, `cerebrum_forget`, and `cerebrum_end_session` in the list.

### Check Ollama Connectivity

Cerebrum contacts Ollama lazily on first use. To verify Ollama is available:

```bash
# Check Ollama is running
curl http://localhost:11434/api/tags

# Verify nomic-embed-text model is available
ollama list | grep nomic-embed-text
```

If Ollama is not running or the model is missing:

```bash
# Start Ollama (if not running)
ollama serve

# In another terminal, pull the model
ollama pull nomic-embed-text
```

---

## Smoke Test

Run this test to verify end-to-end functionality:

```bash
# 1. Store a memory
cerebrum_remember "The capital of France is Paris" 0.9

# 2. Recall it
cerebrum_recall "France capital" 10

# 3. Promote to long-term
# (Use the memory ID from step 1)
cerebrum_memorize <memory-id>

# 4. Verify it's in Cortex
cerebrum_recall "France capital" 10

# 5. End session (clears Synapse, promotes high-salience to Cortex)
cerebrum_end_session 0.7
```

Expected behavior:
- `remember` returns a memory ID
- `recall` returns the stored memory with high relevance
- `memorize` succeeds silently
- `end_session` clears Synapse

---

## Troubleshooting

### Cerebrum Tools Not Appearing

**Symptom:** `cerebrum_*` tools are not available in agents.

**Diagnosis:**
1. Check that the MCP server is registered: `cat ~/.config/opencode/opencode.json | jq '.mcp.cerebrum'`
2. Check that the binary exists: `ls -la ~/.local/share/cerebrum/bin/cerebrum` (or wherever it's deployed)
3. Check OpenCode logs for MCP initialization errors

**Solution:**
```bash
# Re-run home-manager switch to redeploy
home-manager switch --flake .#<machine>

# Restart OpenCode
# (Close and reopen the agent)
```

### Ollama Connection Timeout

**Symptom:** First `remember()` or `recall()` call hangs or times out.

**Diagnosis:**
- Ollama is not running or not responding at `http://localhost:11434`
- The nomic-embed-text model is not loaded (cold-start delay)

**Solution:**
```bash
# 1. Verify Ollama is running
curl http://localhost:11434/api/tags

# 2. If not running, start it
ollama serve

# 3. Verify the model is available
ollama list | grep nomic-embed-text

# 4. If not available, pull it
ollama pull nomic-embed-text

# 5. Retry the operation (first call may be slow as model loads)
```

### Embedding Dimension Mismatch

**Symptom:** `remember()` or `recall()` returns a validation error about embedding dimension.

**Diagnosis:**
- The Ollama model returned embeddings with an unexpected dimension (e.g., 384 instead of 768)
- The configured `embedding_dim` in the server doesn't match the model output

**Solution:**
```bash
# 1. Check the model's actual dimension
ollama show nomic-embed-text | grep embedding_dim

# 2. If it doesn't match 768, either:
#    a. Switch to a model that produces 768-dimensional embeddings
#    b. Update the cerebrum config to match the model's dimension

# 3. Wipe the old LanceDB schema (incompatible with new dimension)
rm -rf ~/.local/share/cerebrum/data/cerebrum/

# 4. Restart Cerebrum (new table created automatically)
home-manager switch --flake .#<machine>
```

### Memory Not Persisting

**Symptom:** Memories stored in Synapse are lost after `end_session()` or restart.

**Diagnosis:**
- This is expected behavior: Synapse is short-term, in-memory storage
- Memories are only persistent if promoted to Cortex via `memorize()` or `end_session()` with high salience

**Solution:**
- Use `cerebrum_memorize` to explicitly promote important memories to Cortex
- Use `cerebrum_end_session` with a low threshold (e.g., 0.3) to auto-promote more memories

### LanceDB Schema Corruption

**Symptom:** Errors about table schema mismatch or incompatible vectors.

**Diagnosis:**
- The LanceDB schema was created with a different embedding dimension
- The embedding model was changed without wiping the old schema

**Solution:**
```bash
# 1. Stop Cerebrum
home-manager switch --flake .#<machine> # (or just kill the process)

# 2. Wipe the old schema
rm -rf ~/.local/share/cerebrum/data/cerebrum/

# 3. Restart Cerebrum (new table created automatically)
home-manager switch --flake .#<machine>

# 4. Re-populate memories via remember() calls
```

---

## Cold-Start Behavior

### MCP Initialization (No Pre-Warm)

When Cerebrum starts:
1. The MCP server initializes instantly (no network I/O)
2. The embedder is constructed but does not contact Ollama
3. The stdio handshake completes immediately
4. Tools are registered and available to agents

This lazy startup pattern avoids blocking the MCP initialization timeout, even if Ollama is warming up a model.

**⚠️ Important:** If you remove the `nomic-embed-text` model (e.g., `ollama rm nomic-embed-text`) while an old Cerebrum binary is still deployed, the old binary will crash on startup because it still contains the blocking warmup probe. To avoid this during cold-start testing:
1. Complete `home-manager switch --flake .#<machine>` to deploy the new lazy binary
2. Then remove the model for testing
3. Restart OpenCode — the new binary will initialize successfully without pre-warming

### First Embedding Request

When the first `remember()` or `recall()` call is made:
1. The embedder contacts Ollama at `http://localhost:11434`
2. If Ollama is not running, the error is returned gracefully (no panic)
3. If the model is not loaded, Ollama loads it (may take 10–30 seconds)
4. The embedding is computed and returned
5. Subsequent calls are faster (model stays in memory)

### Graceful Degradation

If Ollama becomes unavailable after initialization:
- `remember()` and `recall()` return a `CerebrumError::Validation` or network error
- The error is propagated to the MCP tool handler
- The tool returns an error message to the agent (no crash)
- The agent can handle the error and retry or fall back to alternative behavior

---

## Performance Tuning

### Embedding Latency

First embedding request may be slow (10–30 seconds) as Ollama loads the model. Subsequent requests are typically 100–500ms.

**To reduce cold-start latency:**
1. Pre-load the model: `ollama pull nomic-embed-text` before starting Cerebrum
2. Increase Ollama's memory allocation if available
3. Use a faster machine or GPU acceleration (if available)

### Memory Tier Selection

- **Synapse (short-term):** Fast, in-memory, session-scoped. Use for temporary context.
- **Cortex (long-term):** Persistent, searchable across sessions. Use for important facts.

**Strategy:**
- Store frequently-accessed memories in Cortex (via `memorize()`)
- Use Synapse for session-specific context (auto-cleared on `end_session()`)
- Set salience high (0.8–1.0) for important memories to auto-promote on session end

---

## See Also

- [Architecture](architecture.md) — System design and memory tier documentation
- [Modules Reference](modules.md#cerebrum-options) — Cerebrum module configuration
- [Athenaeum Watcher](athenaeum-watcher.md) — Corpus ingestion and file watching (similar lazy-startup pattern)
