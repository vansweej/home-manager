# parallels-ubuntu guest-VM onboarding

## What this is

The `parallels-ubuntu` home-manager profile deploys this repository's
configuration — the OpenCode agents, skills, commands, and tools, plus the
imported ai-os MCP binaries (cerebrum, athenaeum, choragos, argus, pavo) — onto
a Parallels Ubuntu VM so a colleague can get a working AI-coding environment
without hand-assembling one.

It does **not** install the OpenCode binary itself, and it does **not**
install Ollama. Both are left for you to install yourself (see "What you
supply yourself" below).

## CRITICAL: the VM user must be named `parallels`

> Create the Ubuntu user account with the exact username `parallels` (home
> directory `/home/parallels`) **at VM creation time**. This is a deliberate
> distribution convention baked into `machines/parallels-ubuntu.nix`, not a
> placeholder to rename. If the account is named anything else,
> `home-manager switch --flake .#parallels-ubuntu` will target the wrong home
> directory and nothing will land where you expect.

Do this **before** any install steps below.

## Install steps

1. Create the GUI Parallels VM with Ubuntu, naming the user account exactly
   `parallels` as above.
2. Install Nix inside the VM and enable flakes (`experimental-features =
   nix-command flakes` in `nix.conf`, or use the Determinate Systems / official
   multi-user installer which enables flakes by default).
3. Clone this repository anywhere inside the VM (its location does not matter
   — home-manager only needs the flake, not a fixed checkout path).
4. Run the switch:
   ```bash
   home-manager switch -b backup --flake .#parallels-ubuntu
   ```
   The `-b backup` flag is required on this first switch: a freshly created
   Ubuntu account already has `~/.bashrc` and `~/.profile` copied from
   `/etc/skel`, and home-manager refuses to clobber them without it. The
   originals are preserved as `.bashrc.backup` / `.profile.backup`; the flag
   is only needed for the first switch (subsequent switches are clean, though
   leaving it on is harmless).

## opencode.json first-run collision (read before launching OpenCode)

If you install OpenCode yourself and launch it **before** running the switch
above, OpenCode will write a plain `~/.config/opencode/opencode.json` on its
own. home-manager then refuses to overwrite that file on activation, and you
will see an error similar to:

```
Existing file '/home/parallels/.config/opencode/opencode.json' is in the way
```

**Remedy:** the recommended first-run command above
(`home-manager switch -b backup --flake .#parallels-ubuntu`) already handles
this case — `-b backup` backs up any file in the way, not just the shell
dotfiles. If you already ran the switch *without* that flag and hit this
error, remove or move the offending file manually, then re-run:

```bash
rm ~/.config/opencode/opencode.json
# or: mv ~/.config/opencode/opencode.json ~/.config/opencode/opencode.json.bak
home-manager switch -b backup --flake .#parallels-ubuntu
```

**Ordering advice:** run `home-manager switch` **before** first launching
OpenCode to avoid this entirely.

## What you get

- The full OpenCode surface: all agents, skills, commands, and tools
  auto-discovered from `opencode/`.
- Tree-sitter grammars for the `@ai-coding/codebase` `ParserPool`
  (ts/js/rust/c/cpp/python).
- `sccache` (local-only Rust/C++ compiler cache).
- `ghostty` (terminal) and `neovim` (default editor). Neovim's first
  activation runs `bootstrapNvim`, which clones the LazyVim starter — **this
  needs network access** on first switch.
- `starship`, `bat`.
- `services.flameshot`.
- The full MCP stack: **cerebrum** (two-tier agent memory), **athenaeum**
  (corpus search + watcher), **choragos** (plan-cycle orchestrator),
  **argus**, and **pavo** (the argus-companion Rails dashboard).

**This profile deliberately sets no `nixGL` field.** That means:
- No nixGL wrappers (ghostty runs unaccelerated).
- No `.desktop` launcher entries.
- No `xdg.mimeApps`.

In short: no GUI application launchers, and `ghostty` will not be
hardware-accelerated. This is a known, intentional characteristic of the
guest profile, not a bug.

## What you supply yourself

- **OpenCode** itself (the binary this configuration deploys *support
  files* for, not the application).
- **Ollama**, running at `localhost:11434`, with both embedding models pulled:
  athenaeum requires `nomic-embed-text`, while cerebrum requires
  `qwen3-embedding:0.6b` (1024-dimensional). Run:
  ```bash
  ollama pull nomic-embed-text
  ollama pull qwen3-embedding:0.6b
  ```
- `gh auth login` — `gh` is enabled, but not authenticated out of the box.
- **Your own git identity.** The guest ships with no `programs.git.settings.user`
  — set it yourself (`git config --global user.name` / `user.email`, or add a
  `programs.git.settings.user` block to your own fork if you prefer it managed).
- `~/Documents/corpus` — the directory athenaeum's corpus watcher monitors.
  Populate it with PDFs/EPUBs you want indexed.

## Troubleshooting

1. **`home-manager switch` fails with "Existing file '/home/parallels/.bashrc'
   would be clobbered" (and the same for `.profile`).** This is guaranteed on
   every fresh Ubuntu guest, because `/etc/skel` already provides both files
   at account creation. Fix: re-run with
   `home-manager switch -b backup --flake .#parallels-ubuntu`, which moves the
   originals to `.bashrc.backup` / `.profile.backup` and proceeds. Caveat: if
   a previous failed attempt already created those `.backup` files,
   home-manager will refuse to overwrite them too — remove the stale backups
   or pass a different extension (e.g. `-b bak2`) and re-run.
2. **Wrong home directory / switch does nothing useful.** Check that the VM's
   Ubuntu user account is named exactly `parallels`. This is the single most
   common setup mistake — see the CRITICAL callout above.
3. **`home-manager switch` fails with an "existing file is in the way" error
   for `opencode.json`.** See the first-run collision section above: remove
   or move the plain file OpenCode created, then re-run the switch.

## Known limitations

- **pavo's Ruby runtime on aarch64-linux is untested.** pavo evaluates and
  deploys fine — it is consumed as a plain source tree (`flake = false`) and
  resolves its own devShell at runtime — but the Ruby toolchain itself has
  never actually been exercised on aarch64-linux. This is the one genuine
  remaining unknown in this capability set.
- **Minimum-revision note for future maintainers (not a current limitation).**
  athenaeum requires pdfium-render ≥ 0.9.4 (earlier versions hardcode
  `as *const i8`, which fails on AArch64 Linux where `c_char` is `u8`), and
  cerebrum required a dependency-rot fix. Both fixes are already consumed via
  the lock-only commits `800f35b` (athenaeum) and `bb9e9ff` (cerebrum) on
  `main`. Re-pinning `flake.lock` backwards past those commits will
  reintroduce a broken aarch64-linux build.
