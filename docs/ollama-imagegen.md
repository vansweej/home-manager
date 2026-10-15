# `ollama-imagegen` — frozen Ollama 0.32.5 image-generation instance

## Availability

`ollama-imagegen` exists ONLY on M1 and M5 (aarch64-darwin). oryp6 does not get
the command and reaches the M5 instance only through `ollama-tunnel`.

## Purpose and version

This is a frozen, hash-pinned, single-purpose image-generation Ollama instance.
It runs Ollama 0.32.5 separately from the daily Ollama.app.

## Policy

Fast-moving AI tools used daily (Ollama.app, OpenCode) are installed and updated by the user with their own updaters, not via home-manager/Nix/brew, because package managers lag several versions behind and that has caused problems before. That rule does not apply to a deliberately frozen, hash-pinned, single-purpose artifact: such an artifact (here Ollama 0.32.5 as `ollama-imagegen`) should be managed declaratively by home-manager, because automating its many manual steps is the point and staying behind is intentional. It must never shadow or interfere with the daily tool (separate command name, port and models dir).

## Distribution

The module uses `ollama-darwin.tgz`, the standalone CLI distribution containing
the same Apple-signed/notarized Developer ID binaries as inside the app.
`/nix/store` files carry no quarantine xattr. The derivation extracts in place
and never chmods, moves, or relocates the binary: Ollama finds runner libs
relative to its executable, and signed files stay byte-identical.

## Commands

```bash
ollama-imagegen start | stop | status | logs | help
```

Everything else (`serve`, `pull`, `list`, `ps`, `rm`, `show`, `--version`, …)
passes through to the frozen binary at `127.0.0.1:11436`.

## Environment isolation

The wrapper clears EVERY inherited `OLLAMA_*` variable, so
`launchctl setenv OLLAMA_HOST=0.0.0.0`, `OLLAMA_ORIGINS`, `OLLAMA_KEEP_ALIVE`,
and other daily-Ollama environment cannot leak in. It then exports only
`OLLAMA_HOST=127.0.0.1:11436` and `OLLAMA_MODELS=<models dir>`.

## Foreground serves

`start` detects a healthy-but-untracked instance, such as a foreground
`ollama-imagegen serve`, and refuses to start a second one. `stop` reports that
it cannot stop an untracked instance and to Ctrl-C it in its terminal. `status`
marks a healthy instance without a tracked PID as `untracked`.

## Paths

- Models: `~/.local/share/ollama-imagegen/models`
- State: `~/.local/state/ollama-imagegen`
- PID file: `serve.pid`
- Log: `serve.log`

## Coexistence with Ollama.app

The daily Ollama.app remains on port `11434`; this instance uses `11436` and its
own models directory, so they never share state. Check that Ollama.app remains
untouched with:

```bash
curl -fsS 127.0.0.1:11434/api/version
```

## First-time steps

After `home-manager switch` on the Mac:

1. Verify `ollama-imagegen --version` reports `0.32.5`.
2. Run `ollama-imagegen start`, then `ollama-imagegen status`.
3. Pull a model, for example `ollama-imagegen pull x/flux2-klein` (4B, ~5.7 GB)
   or `ollama-imagegen pull x/z-image-turbo` (~13 GB fp8).
4. Test an image call:

   ```bash
   curl -s http://127.0.0.1:11436/v1/images/generations \
     -H 'Content-Type: application/json' \
     -d '{"model":"x/flux2-klein","prompt":"a red fox in snow","size":"512x512"}' | head -c 300
   ```

5. From oryp6, reach it through `ollama-tunnel` (run from `~/Work/comfyui`,
   default `REMOTE_PORT 11436`).

## Verification checklist

Real verification happens on the Mac after switch: confirm `--version` is
`0.32.5`; run `start` and `status`; pull one model; make an image call; reach it
from oryp6 via `ollama-tunnel`; and confirm Ollama.app remains untouched with
`curl 127.0.0.1:11434/api/version`.

## Troubleshooting

- Check a busy port with `/usr/sbin/lsof -nP -iTCP:11436 -sTCP:LISTEN -t`.
- Lid-close or MDM sleep can stop the background serve; run `start` again.
- Allow roughly 19 GB of disk for both example models.
- To upgrade, change `version` and `hash` in `modules/ollama-imagegen.nix`.
- To remove the instance, drop its import. The models directory is **not**
  auto-deleted.
- **Zip fallback:** use `Ollama-darwin.zip` v0.32.5 (sha256 hex
  `729396bb6fea20df0f3792087f363b90465e68f7f596fcb4b5926929b0dce4d8`) and run
  `Ollama.app/Contents/Resources/ollama` from the store via the same runtime
  detection, never launching the `.app`. Switch by editing the `sources`
  attrset (`url` and `hash`).
