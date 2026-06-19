# Athenaeum corpus watcher runbook

Operational guide for the `athenaeum-watch` service that reingests the corpus when
files change. For the module design and options, see
[the module reference](modules.md#corpus-watcher-options).

## What it does

A long-running `watchexec` process watches `~/Documents/corpus`. On each debounced
change it runs the short-lived `athenaeum-ingest` CLI over the whole directory.
`watchexec` is the only resident process — athenaeum itself is never a daemon.

- **No reingest at startup.** The watcher runs with `--postpone`, so a
  `home-manager switch` or reboot does **not** trigger a reingest — only a genuine
  post-startup change does. Backfill manually (see [Manual reingest](#manual-reingest)).
- **Debounce.** Changes are coalesced over a 5 s window, so a burst of file drops
  produces one reingest, and a partially-written file is not ingested mid-write.
- **Requires Ollama** at `localhost:11434` with the `nomic-embed-text` model, the
  same dependency as manual ingest. With Ollama down, ingest fails and nothing is
  written.

## Per-OS unit

| OS | Unit | Manager |
|---|---|---|
| Linux (oryp6) | `athenaeum-watch` | `systemd.user.services` |
| macOS (M1, M5) | `athenaeum-watch` | `launchd.agents` |

## Check it is running

**Linux:**

```bash
systemctl --user status athenaeum-watch
```

Expect `Active: active (running)`.

**macOS:**

```bash
launchctl list | grep athenaeum-watch
```

Expect a line with a numeric PID in the first column. A `-` instead of a PID means
it is loaded but not currently running.

## View logs

**Linux** (logs go to the systemd journal):

```bash
journalctl --user -u athenaeum-watch -f
```

**macOS** (launchd has no journal; logs go to files under the data dir):

```bash
tail -f ~/.local/share/athenaeum/watch.log
tail -f ~/.local/share/athenaeum/watch.err.log
```

## Smoke test

1. Copy a PDF or EPUB into `~/Documents/corpus`.
2. Wait at least 5 seconds (the debounce window).
3. Confirm exactly **one** reingest cycle in the logs (Linux: `journalctl`; macOS:
   `watch.log`).

Because ingest upserts per file (delete-then-add keyed on the absolute path),
re-running over an unchanged corpus does not duplicate rows. The MCP server picks
up new content on its next `athenaeum_search` — no restart needed.

## Start / stop / restart

**Linux:**

```bash
systemctl --user start athenaeum-watch
systemctl --user stop athenaeum-watch
systemctl --user restart athenaeum-watch
```

**macOS:** the agent is managed by home-manager, so the normal way to reload it is a
switch:

```bash
home-manager switch --flake ~/Projects/home-manager#M5   # or #M1
```

For debugging, first discover the launchd label (home-manager sets it), then act on
that service target:

```bash
launchctl list | grep athenaeum          # find the label, e.g. ...athenaeum-watch
launchctl kickstart -k gui/$(id -u)/<label>   # restart
launchctl bootout    gui/$(id -u)/<label>     # stop (until next switch / login)
```

Replace `<label>` with the value printed by the first command.

## Manual reingest

The watcher does **not** ingest at startup (`--postpone`), so files added while it
was stopped are not picked up automatically. Backfill them by running the CLI from
the data dir, so its relative `./data/athenaeum` db_path resolves to the shared
store:

```bash
cd ~/.local/share/athenaeum
athenaeum-ingest ~/Documents/corpus --recursive --verbose
```

## Troubleshooting

**Watcher does not react to a new file**
Confirm the unit is running (see [Check it is running](#check-it-is-running)) and
wait out the full 5 s debounce window.

**Log shows ingest errors, nothing is added**
Ollama is almost certainly not reachable. Confirm it is serving at `localhost:11434`
with the `nomic-embed-text` model pulled, then re-trigger with a manual reingest.

**A stray `data/athenaeum` directory appears inside `~/Documents/corpus`**
This should never happen from the unit — both `watchexec --workdir` and the unit's
working directory pin cwd to `~/.local/share/athenaeum`. It only occurs if a manual
`athenaeum-ingest` was run from inside the corpus dir. Always run manual ingests
from the data dir (see [Manual reingest](#manual-reingest)) and delete the stray
directory.

**A deleted file still shows up in search results**
Known limitation: deleting a file from the corpus does not remove its embeddings —
there is no prune path yet. The embeddings persist until the store is rebuilt.

## See also

- [Module reference — corpus watcher options](modules.md#corpus-watcher-options)
- The "Corpus directory watcher" and "Running bulk ingest" sections in the
  repository `AGENTS.md`
