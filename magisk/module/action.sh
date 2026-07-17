#!/system/bin/sh
# ESurfing Daemon — KernelSU / Magisk action.sh
# Toggle daemon start/stop without rebooting the phone.
# KernelSU Manager shows an "Action" button for modules that ship this file.

MODDIR=${0%/*}
DATA_DIR=/data/adb/esurfing
BIN="$DATA_DIR/esurfingd"
PID_FILE="$DATA_DIR/esurfingd.pid"
DISABLE_FLAG="$DATA_DIR/disable"
LOG="$DATA_DIR/run.log"

log() {
  echo "[action] $1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [action] $1" >> "$LOG" 2>/dev/null || true
}

is_running() {
  # Prefer PID file, fall back to process name
  if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
      # Confirm it's our binary when possible
      if [ -r "/proc/$pid/cmdline" ]; then
        tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q esurfingd && return 0
      else
        return 0
      fi
    fi
  fi
  pidof esurfingd >/dev/null 2>&1 && return 0
  return 1
}

ensure_files() {
  mkdir -p "$DATA_DIR/portal" "$DATA_DIR/webroot"
  if [ ! -x "$BIN" ]; then
    if [ -f "$MODDIR/esurfingd" ]; then
      cp "$MODDIR/esurfingd" "$BIN"
      chmod 755 "$BIN"
    else
      log "ERROR: daemon binary not found at $BIN"
      echo "错误: 找不到守护进程二进制"
      exit 1
    fi
  fi
  # Keep portal/webroot in sync when starting from action
  cp -r "$MODDIR/portal/"* "$DATA_DIR/portal/" 2>/dev/null || true
  cp -r "$MODDIR/webroot/"* "$DATA_DIR/webroot/" 2>/dev/null || true
  if [ ! -f "$DATA_DIR/ESurfingClient.json" ] && [ -f "$MODDIR/ESurfingClient.json" ]; then
    cp "$MODDIR/ESurfingClient.json" "$DATA_DIR/"
  fi
}

stop_daemon() {
  log "Stopping esurfingd..."
  touch "$DISABLE_FLAG"
  # Prefer graceful stop via HTTP API (clean shut)
  if is_running; then
    if command -v curl >/dev/null 2>&1; then
      curl -sS -m 3 -X POST "http://127.0.0.1:8888/api/stop" >/dev/null 2>&1 || true
      i=0
      while [ $i -lt 20 ]; do
        is_running || break
        sleep 0.2
        i=$((i + 1))
      done
    fi
  fi
  # Fallback: SIGTERM then SIGKILL
  if is_running; then
    if [ -f "$PID_FILE" ]; then
      kill "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null || true
    fi
    killall esurfingd 2>/dev/null || true
    sleep 0.5
  fi
  if is_running; then
    killall -9 esurfingd 2>/dev/null || true
    sleep 0.3
  fi
  rm -f "$PID_FILE"
  if is_running; then
    log "Failed to stop esurfingd"
    echo "停止失败：进程仍在运行"
    exit 1
  fi
  log "esurfingd stopped (disable flag set)"
  echo "已停止守护进程（无需重启手机）"
  echo "下次开机也不会自动启动，直到再次执行 Action 启动"
}

start_daemon() {
  log "Starting esurfingd..."
  ensure_files
  rm -f "$DISABLE_FLAG"
  if is_running; then
    log "Already running"
    echo "守护进程已在运行"
    exit 0
  fi
  # Launch detached so action.sh can return
  # nohup + redirect keeps it alive after action exits
  (
    cd "$DATA_DIR" || exit 1
    # shellcheck disable=SC2086
    nohup "$BIN" >>"$LOG" 2>&1 &
  )
  sleep 0.8
  if is_running; then
    log "esurfingd started"
    echo "已启动守护进程（无需重启手机）"
    echo "Web: http://127.0.0.1:8888/"
    exit 0
  fi
  # Some environments lack nohup; retry with plain background
  (
    cd "$DATA_DIR" || exit 1
    "$BIN" >>"$LOG" 2>&1 &
  )
  sleep 0.8
  if is_running; then
    log "esurfingd started (fallback)"
    echo "已启动守护进程（无需重启手机）"
    echo "Web: http://127.0.0.1:8888/"
    exit 0
  fi
  log "Failed to start esurfingd"
  echo "启动失败，请查看 $LOG"
  exit 1
}

# Main: toggle
if is_running; then
  stop_daemon
else
  start_daemon
fi
