# Home Manager Configuration

Nix flake-based home-manager configuration for user `vansweej` on x86_64-linux.

## Apply Configuration

```bash
home-manager switch --flake .#nixhero-home
```

## Structure

- `flake.nix` - Flake inputs and home configuration definition
- `home.nix` - Packages, programs, and dotfiles managed by home-manager
- `opencode/AGENTS.md` - Global OpenCode agent instructions (deployed to `~/.config/opencode/AGENTS.md`)
- `opencode/skill/*/SKILL.md` - OpenCode skills (deployed to `~/.config/opencode/skill/`)

## Key Packages

- `ghostty-nixgl` - Custom wrapper script that runs ghostty with nixGLIntel for hardware acceleration
- `nixgl.nixGLIntel` - OpenGL wrapper for Nix on non-NixOS
- `ghostty` - GPU-accelerated terminal emulator
- `nerd-fonts.fira-code` - Font
- `opencode` - AI coding agent
- `ollama` - Local LLM server (runs as user systemd service with CUDA acceleration)

## Ollama

Configured via `services.ollama` with `acceleration = "cuda"`. Starts automatically on login, listens on `127.0.0.1:11434`. Pull models with `ollama pull <model>`.
