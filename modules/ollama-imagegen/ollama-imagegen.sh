# ---------------------------------------------------------------------------
# ollama-imagegen wrapper (subcommands) — concatenated after the Nix preamble
# which defines: IG_ROOT IG_HOST IG_MODELS IG_STATE (plain, non-exported).
# ---------------------------------------------------------------------------

# Isolate from the daily Ollama: clear EVERY inherited OLLAMA_* variable so a
# `launchctl setenv OLLAMA_HOST=0.0.0.0`, OLLAMA_ORIGINS, OLLAMA_KEEP_ALIVE,
# etc. cannot leak into this frozen instance.
while IFS= read -r _v; do
  unset "$_v"
done < <(compgen -v OLLAMA_ || true)

export OLLAMA_HOST="$IG_HOST"
export OLLAMA_MODELS="$IG_MODELS"

# Resolve the frozen binary at runtime (never baked into the Nix store path of
# the wrapper; found relative to IG_ROOT so Ollama locates its runner libs).
if [ -x "$IG_ROOT/ollama" ]; then
  IG_BIN="$IG_ROOT/ollama"
elif [ -x "$IG_ROOT/bin/ollama" ]; then
  IG_BIN="$IG_ROOT/bin/ollama"
else
  printf 'ollama-imagegen: frozen ollama binary not found or not executable under %s\n' "$IG_ROOT" >&2
  exit 1
fi

PIDFILE="$IG_STATE/serve.pid"
LOGFILE="$IG_STATE/serve.log"
VERSION_URL="http://$IG_HOST/api/version"
LSOF="/usr/sbin/lsof"

mkdir -p "$IG_STATE" "$IG_MODELS"

ig_port() { printf '%s' "$IG_HOST" | cut -d: -f2; }

ig_version() { curl -fsS --max-time 3 "$VERSION_URL" 2>/dev/null; }

ig_healthy() { ig_version >/dev/null 2>&1; }

# Prints the tracked pid and returns 0 if it is alive; returns 1 otherwise.
ig_tracked_pid() {
  if [ -f "$PIDFILE" ]; then
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      printf '%s' "$pid"
      return 0
    fi
  fi
  return 1
}

# Returns 0 if something is LISTENing on our port. Prints nothing.
# If lsof is missing, warns once and returns 1 (treated as "cannot tell").
ig_port_listening() {
  if [ ! -x "$LSOF" ]; then
    printf 'ollama-imagegen: %s not found; skipping port-listen check\n' "$LSOF" >&2
    return 1
  fi
  local port
  port="$(ig_port)"
  [ -n "$("$LSOF" -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null)" ]
}

cmd_start() {
  local pid
  if pid="$(ig_tracked_pid)"; then
    if ig_healthy; then
      printf 'ollama-imagegen: already running (pid %s), healthy on %s\n' "$pid" "$IG_HOST"
      return 0
    fi
    printf 'ollama-imagegen: tracked pid %s is alive but not answering on %s yet; see "ollama-imagegen logs" or run "ollama-imagegen stop"\n' "$pid" "$IG_HOST" >&2
    return 1
  fi

  if ig_healthy; then
    printf 'ollama-imagegen: an untracked ollama-imagegen/serve is already answering on %s (probably a foreground ollama-imagegen serve); not starting a second one\n' "$IG_HOST"
    return 0
  fi

  if ig_port_listening; then
    printf 'ollama-imagegen: something is LISTENing on %s but does not answer %s; refusing to start\n' "$IG_HOST" "$VERSION_URL" >&2
    return 1
  fi

  nohup "$IG_BIN" serve >>"$LOGFILE" 2>&1 &
  local newpid=$!
  printf '%s' "$newpid" >"$PIDFILE"

  for _ in $(seq 1 30); do
    if ig_healthy; then
      printf 'ollama-imagegen: started (pid %s) — %s\n' "$newpid" "$(ig_version)"
      printf 'log: %s\n' "$LOGFILE"
      return 0
    fi
    if ! kill -0 "$newpid" 2>/dev/null; then
      printf 'ollama-imagegen: serve process (pid %s) died during startup; last 20 log lines:\n' "$newpid" >&2
      tail -n 20 "$LOGFILE" >&2 2>/dev/null || true
      rm -f "$PIDFILE"
      return 1
    fi
    sleep 1
  done

  printf 'ollama-imagegen: timed out waiting for %s after 30s; last 20 log lines:\n' "$VERSION_URL" >&2
  tail -n 20 "$LOGFILE" >&2 2>/dev/null || true
  return 1
}

cmd_stop() {
  local pid
  if pid="$(ig_tracked_pid)"; then
    kill -TERM "$pid" 2>/dev/null || true
    for _ in $(seq 1 10); do
      if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$PIDFILE"
        printf 'ollama-imagegen: stopped (pid %s)\n' "$pid"
        return 0
      fi
      sleep 1
    done
    kill -KILL "$pid" 2>/dev/null || true
    rm -f "$PIDFILE"
    printf 'ollama-imagegen: force-killed (pid %s)\n' "$pid"
    return 0
  fi

  if ig_healthy; then
    printf 'ollama-imagegen: untracked instance on %s (foreground serve?) — stop it with Ctrl-C in its terminal\n' "$IG_HOST" >&2
    return 1
  fi

  rm -f "$PIDFILE"
  printf 'ollama-imagegen: not running\n'
  return 0
}

cmd_status() {
  local pid
  if pid="$(ig_tracked_pid)"; then
    printf 'pid:        %s (alive)\n' "$pid"
  elif [ -f "$PIDFILE" ]; then
    printf 'pid:        stale pidfile (%s)\n' "$PIDFILE"
  else
    printf 'pid:        not running\n'
  fi

  if ig_healthy; then
    if ig_tracked_pid >/dev/null; then
      printf 'listening:  yes (%s)\n' "$IG_HOST"
    else
      printf 'listening:  yes (%s, untracked)\n' "$IG_HOST"
    fi
    printf 'version:    %s\n' "$(ig_version)"
  else
    printf 'listening:  no\n'
    printf 'version:    (unavailable)\n'
  fi

  printf 'binary:     %s\n' "$IG_BIN"
  printf 'models dir: %s\n' "$IG_MODELS"
  if [ -d "$IG_MODELS" ]; then
    printf 'models size:%s\n' " $(du -sh "$IG_MODELS" 2>/dev/null | cut -f1)"
  fi
  printf 'state dir:  %s\n' "$IG_STATE"
  printf 'log:        %s\n' "$LOGFILE"
  return 0
}

cmd_logs() {
  touch "$LOGFILE"
  tail -n 100 -f "$LOGFILE"
}

cmd_help() {
  cat <<'EOF'
ollama-imagegen — frozen Ollama 0.32.5 image-generation instance

Wrapper subcommands:
  start     start the frozen serve in the background (port 127.0.0.1:11436)
  stop      stop the background serve tracked via the pidfile
  status    show pid / listening / version / paths
  logs      tail -f the serve log
  help      show this message

Any other argument (serve, pull, list, ps, rm, show, --version, ...) is passed
straight through to the frozen ollama binary, talking to 127.0.0.1:11436.
EOF
}

case "${1:-}" in
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  logs)   cmd_logs ;;
  help)   cmd_help ;;
  *)      exec "$IG_BIN" "$@" ;;
esac
